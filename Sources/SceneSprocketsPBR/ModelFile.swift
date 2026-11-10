import Foundation
import Metal
import MetalSprocketsGLTF
import MetalSupport
import SceneSprockets
import UniformTypeIdentifiers

/// Loads a model file of any supported format into one subtree, to insert into a scene.
///
/// glTF files (`.gltf`, `.glb`) load with ``GLTFSceneGraph``. The formats that Model I/O reads (`.usdz`, `.usd`, `.obj`,
/// `.ply`, `.stl`, `.abc`) load with ``ModelIOSceneGraph``.
public enum ModelFile {
    /// The file extensions that load with ``GLTFSceneGraph``.
    public static let glTFExtensions: Set<String> = ["gltf", "glb"]
    /// The file extensions that load with ``ModelIOSceneGraph``.
    public static let modelIOExtensions: Set<String> = ["usdz", "usd", "usda", "usdc", "obj", "ply", "stl", "abc"]

    /// The content types of all supported files, for example for a file importer.
    public static var contentTypes: [UTType] {
        (glTFExtensions.union(modelIOExtensions)).sorted().compactMap { UTType(filenameExtension: $0) }
    }

    /// Errors from loading a model file.
    public enum Failure: Error, CustomStringConvertible {
        /// The file extension is not a supported format. The value is the extension.
        case unsupportedFormat(String)

        public var description: String {
            switch self {
            case .unsupportedFormat(let pathExtension):
                "Cannot read .\(pathExtension) files"
            }
        }
    }

    /// Whether `url` loads other files by relative URI (buffers or images that are not data URIs). In the App Sandbox
    /// the user must then grant its folder, as the MetalSprocketsGLTF GLTFViewer demo does (#206). .glb files are
    /// treated as self-contained.
    public static func needsFolderAccess(_ url: URL) throws -> Bool {
        try !externalFiles(url).isEmpty
    }

    /// The distinct relative URIs of the buffers and images a .gltf loads from other files, in order (#213). Empty for
    /// other formats and for data URIs.
    public static func externalFiles(_ url: URL) throws -> [String] {
        guard url.pathExtension.lowercased() == "gltf" else {
            return []
        }
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any] ?? [:]
        let resources = (json["buffers"] as? [[String: Any]] ?? []) + (json["images"] as? [[String: Any]] ?? [])
        var seen = Set<String>()
        return resources.compactMap { resource in
            guard let uri = resource["uri"] as? String, !uri.hasPrefix("data:"), seen.insert(uri).inserted else {
                return nil
            }
            return uri.removingPercentEncoding ?? uri
        }
    }

    /// Whether `file` is inside `folder`. Symlinks are resolved, because the two may reach the same place by different
    /// paths.
    public static func isFile(_ file: URL, inside folder: URL) -> Bool {
        let folderPath = folder.resolvingSymlinksInPath().standardizedFileURL.path
        return file.resolvingSymlinksInPath().standardizedFileURL.path.hasPrefix(folderPath.hasSuffix("/") ? folderPath : folderPath + "/")
    }

    /// The file's scene under one node named after the file, detached from any scene graph. Animations are not kept.
    /// A glTF root keeps the file and the buffers and images it loads as its modelSource, so a scene archive can store
    /// the file instead of the subtree (#157).
    public static func load(_ url: URL) throws -> (node: SceneGraph.Node, warnings: [String]) {
        let pathExtension = url.pathExtension.lowercased()
        let root: SceneGraph.Node
        let warnings: [String]
        if glTFExtensions.contains(pathExtension) {
            let result = try GLTFAsset(url: url, device: _MTLCreateSystemDefaultDevice()).makeSceneGraph()
            root = result.sceneGraph.root
            warnings = result.warnings
            root.modelSource = try SceneGraph.ModelSource(url: url, relatedFiles: externalFiles(url))
        } else if modelIOExtensions.contains(pathExtension) {
            let result = try ModelIOSceneGraph(url: url)
            root = result.sceneGraph.root
            warnings = result.warnings
        } else {
            throw Failure.unsupportedFormat(pathExtension)
        }
        root.label = url.deletingPathExtension().lastPathComponent
        return (root, warnings)
    }
}

/// The loader that `SceneArchive` uses for models that a scene package keeps by reference.
public struct ModelFileLoader: ArchivableModelLoader {
    /// Creates a model file loader.
    public init() {}

    public func load(_ url: URL, context _: SceneArchiveContext) throws -> (node: SceneGraph.Node, warnings: [String]) {
        try ModelFile.load(url)
    }
}
