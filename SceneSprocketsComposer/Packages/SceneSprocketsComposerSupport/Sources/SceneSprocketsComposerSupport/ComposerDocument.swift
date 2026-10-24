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

extension SceneArchive {
    static var composer: SceneArchive {
        SceneArchive(materialTypes: [BlinnPhongSceneMaterial.self, PBRSceneMaterial.self], environmentMapTypes: [PBREnvironment.self])
    }
}

private let logger = Logger(subsystem: "io.schwa.SceneSprocketsComposer", category: "Document")

// A .scenesprocketsd bundle, read and written by SceneArchive.
// Unchecked Sendable: SwiftUI reads and snapshots the document on the main actor; writing uses only the snapshot.
public final class ComposerDocument: ReferenceFileDocument, @unchecked Sendable {
    public static let readableContentTypes: [UTType] = [.sceneSprocketsDocument]

    public let sceneGraph: SceneGraph
    // Read from editor.json; nil for new documents or when the file is missing or unreadable.
    let editorState: EditorState?
    // The open editor, whose state is saved with the document.
    weak var editorModel: EditorModel?

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
        // SceneArchive reads from a URL, so copy the bundle out of the file wrapper first.
        let url = try Self.makeTemporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try configuration.file.write(to: url, options: [], originalContentsURL: nil)
        try self.init(contentsOf: url)
    }

    // For readers outside DocumentGroup, such as the Quick Look extension.
    public convenience init(contentsOf url: URL) throws {
        let result = try SceneArchive.composer.read(from: url, device: systemDefaultDevice())
        Self.log(result.warnings)
        self.init(sceneGraph: result.sceneGraph, editorState: EditorState.read(fromBundleAt: url))
    }

    // The bundle is built here, on the main actor, so writing never touches the live scene graph.
    public func snapshot(contentType _: UTType) throws -> FileWrapper {
        let url = try Self.makeTemporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        Self.log(try SceneArchive.composer.write(sceneGraph, to: url))
        // Saving still works without a preview or editor state.
        MainActor.assumeIsolated {
            do {
                try (editorModel?.editorState ?? editorState)?.write(toBundleAt: url)
            } catch {
                logger.warning("Could not write the editor state: \(error, privacy: .public)")
            }
            do {
                try DocumentPreview.write(sceneGraph, into: url, device: systemDefaultDevice())
            } catch {
                logger.warning("Could not write the preview: \(error, privacy: .public)")
            }
        }
        return try FileWrapper(url: url, options: .immediate)
    }

    public func fileWrapper(snapshot: FileWrapper, configuration _: WriteConfiguration) -> FileWrapper {
        snapshot
    }

    private static func makeTemporaryURL() throws -> URL {
        let directory = try FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: FileManager.default.temporaryDirectory, create: true)
        return directory.appendingPathComponent("Scene").appendingPathExtension(SceneArchive.pathExtension)
    }

    private static func log(_ warnings: [String]) {
        for warning in warnings {
            logger.warning("\(warning, privacy: .public)")
        }
    }
}

func systemDefaultDevice() -> any MTLDevice {
    guard let device = MTLCreateSystemDefaultDevice() else {
        fatalError("Metal is not available")
    }
    return device
}
