import Combine
import Foundation
import Metal
import MetalSprocketsPBR
import os
import SceneSprockets
import SceneSprocketsBlinnPhong
import SceneSprocketsPBR
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    public static let sceneSprocketsDocument = UTType(exportedAs: "io.schwa.scenesprockets-document", conformingTo: .package)
}

extension Archive {
    static var composer: Archive {
        // Imported glTF files are kept as they are (#157); other meshes that are not shapes are saved as glTF (#158).
        Archive(materialTypes: [BlinnPhongSceneMaterial.self, PBRSceneMaterial.self], environmentMapTypes: [PBREnvironment.self], meshCodec: GLTFMeshCodec(), modelLoader: ModelFileLoader())
    }
}

private let logger = Logger(subsystem: "io.schwa.SceneSprocketsComposer", category: "Document")

// A .scenesprocketsd bundle, read and written by Archive.
// Unchecked Sendable: the scene graph and editor are used only on the main actor. Off the main actor, snapshot reads
// only the locked captures (#227).
public final class ComposerDocument: ReferenceFileDocument, @unchecked Sendable {
    public static let readableContentTypes: [UTType] = [.sceneSprocketsDocument]

    public let sceneGraph: SceneGraph
    // Read from editor.json; nil for new documents or when the file is missing or unreadable.
    let editorState: EditorState?
    // The open editor. Only main-actor code reads it; saving uses `savedEditorState`.
    weak var editorModel: EditorModel?
    // The editor state to save, copied from the editor on the main actor. snapshot can run on any thread (#204).
    private let savedEditorStateLock = OSAllocatedUnfairLock<EditorState?>(initialState: nil)

    var savedEditorState: EditorState? {
        savedEditorStateLock.withLock { $0 } ?? editorState
    }

    // Call when the editor state changes.
    @MainActor
    func updateEditorState() {
        let state = editorModel?.editorState
        savedEditorStateLock.withLock { $0 = state }
    }

    // The scene to save off the main actor, captured after each undoable change (#227, #238).
    private let savedSceneLock = OSAllocatedUnfairLock<Archive.Capture?>(initialState: nil)
    @MainActor private let textureCache = Archive.TextureCache()
    @MainActor private var isSceneCapturePending = false
    @MainActor private var undoObservers: [any NSObjectProtocol] = []

    // Copies the editor state now and again whenever its inputs change, instead of on every view update (#232).
    // Captures the scene now and after every undoable change, for saving off the main actor (#227).
    @MainActor
    func attach(_ model: EditorModel) {
        editorModel = model
        trackEditorState()
        captureScene()
        undoObservers = [Notification.Name.NSUndoManagerDidCloseUndoGroup, .NSUndoManagerDidUndoChange, .NSUndoManagerDidRedoChange].map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                let sender = (notification.object as? UndoManager).map(ObjectIdentifier.init)
                MainActor.assumeIsolated {
                    guard let self, let undoManager = self.editorModel?.undoManager, sender == ObjectIdentifier(undoManager) else {
                        return
                    }
                    self.scheduleSceneCapture()
                }
            }
        }
    }

    // Several notifications can arrive for one change; capture once, after they settle.
    @MainActor
    private func scheduleSceneCapture() {
        guard !isSceneCapturePending else {
            return
        }
        isSceneCapturePending = true
        Task { @MainActor in
            isSceneCapturePending = false
            captureScene()
        }
    }

    @MainActor
    @discardableResult
    private func captureScene() -> Archive.Capture? {
        do {
            let capture = try Archive.composer.capture(sceneGraph, textureCache: textureCache)
            savedSceneLock.withLock { $0 = capture }
            return capture
        } catch {
            logger.warning("Could not capture the scene: \(error, privacy: .public)")
            return nil
        }
    }

    @MainActor
    private func trackEditorState() {
        guard let model = editorModel else {
            return
        }
        let state = withObservationTracking {
            model.editorState
        } onChange: { [weak self] in
            // Runs before the change lands, so copy on the next main-actor turn.
            Task { @MainActor in
                self?.trackEditorState()
            }
        }
        savedEditorStateLock.withLock { $0 = state }
    }

    public init(sceneGraph: SceneGraph) {
        self.sceneGraph = sceneGraph
        editorState = nil
    }

    init(sceneGraph: SceneGraph, editorState: EditorState?) {
        self.sceneGraph = sceneGraph
        self.editorState = editorState
    }

    public convenience init() {
        self.init(sceneGraph: .empty())
    }

    public convenience init(configuration: ReadConfiguration) throws {
        // Archive reads from a URL, so copy the bundle out of the file wrapper first.
        let url = try Self.makeTemporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try configuration.file.write(to: url, options: [], originalContentsURL: nil)
        try self.init(contentsOf: url)
    }

    // For readers outside DocumentGroup, such as the Quick Look extension.
    public convenience init(contentsOf url: URL) throws {
        let result = try Archive.composer.read(from: url)
        Self.log(result.warnings)
        self.init(sceneGraph: result.sceneGraph, editorState: EditorState.read(fromBundleAt: url))
    }

    // The bundle is built here. SwiftUI usually calls this on the main actor, but AppKit calls it on a background
    // queue when saving on quit, with the main thread blocked (#204). On the main actor it captures the scene now;
    // elsewhere it uses the last capture and never touches the live graph (#227).
    public func snapshot(contentType _: UTType) throws -> FileWrapper {
        let url = try Self.makeTemporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        if Thread.isMainThread {
            try MainActor.assumeIsolated {
                let capture = try Archive.composer.capture(sceneGraph, textureCache: textureCache)
                savedSceneLock.withLock { $0 = capture }
                try write(capture, to: url)
                // Saving still works without a preview.
                do {
                    try DocumentPreview.write(sceneGraph, into: url)
                } catch {
                    logger.warning("Could not write the preview: \(error, privacy: .public)")
                }
            }
        } else {
            guard let capture = savedSceneLock.withLock({ $0 }) else {
                throw CocoaError(.fileWriteUnknown)
            }
            try write(capture, to: url)
            // The preview comes from the bundle just written, a private copy of the captured scene.
            do {
                let saved = try Archive.composer.read(from: url)
                try DocumentPreview.write(saved.sceneGraph, into: url)
            } catch {
                logger.warning("Could not write the preview: \(error, privacy: .public)")
            }
        }
        return try FileWrapper(url: url, options: .immediate)
    }

    // The scene files and editor state. Any thread.
    private func write(_ capture: Archive.Capture, to url: URL) throws {
        Self.log(capture.warnings)
        try capture.write(to: url)
        // Saving still works without the editor state.
        do {
            try savedEditorState?.write(toBundleAt: url)
        } catch {
            logger.warning("Could not write the editor state: \(error, privacy: .public)")
        }
    }

    public func fileWrapper(snapshot: FileWrapper, configuration _: WriteConfiguration) -> FileWrapper {
        snapshot
    }

    private static func makeTemporaryURL() throws -> URL {
        let directory = try FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: FileManager.default.temporaryDirectory, create: true)
        return directory.appendingPathComponent("Scene").appendingPathExtension(Archive.pathExtension)
    }

    private static func log(_ warnings: [String]) {
        for warning in warnings {
            logger.warning("\(warning, privacy: .public)")
        }
    }
}
