import Foundation
import Metal
import MetalSprocketsGLTF
import SceneSprockets
import UniformTypeIdentifiers

// Loads a model file into one subtree, whatever its format: glTF (.gltf, .glb) with GLTFSceneGraph, and everything
// Model I/O reads (.usdz, .usd, .obj, .ply, .stl, .abc) with ModelIOSceneGraph. For inserting into a scene.
public enum ModelFile {
    public static let glTFExtensions: Set<String> = ["gltf", "glb"]
    public static let modelIOExtensions: Set<String> = ["usdz", "usd", "usda", "usdc", "obj", "ply", "stl", "abc"]

    public static var contentTypes: [UTType] {
        (glTFExtensions.union(modelIOExtensions)).sorted().compactMap { UTType(filenameExtension: $0) }
    }

    public enum Failure: Error, CustomStringConvertible {
        case unsupportedFormat(String)

        public var description: String {
            switch self {
            case .unsupportedFormat(let pathExtension):
                "Cannot read .\(pathExtension) files"
            }
        }
    }

    // Whether `url` loads other files by relative URI (buffers or images that are not data URIs). In the App Sandbox
    // the user must then grant its folder, as the MetalSprocketsGLTF GLTFViewer demo does (#206). .glb files are
    // treated as self-contained.
    public static func needsFolderAccess(_ url: URL) throws -> Bool {
        try !externalFiles(url).isEmpty
    }

    // The distinct relative URIs of the buffers and images a .gltf loads from other files, in order (#213). Empty for
    // other formats and for data URIs.
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

    // Whether `file` is inside `folder`. Symlinks are resolved, because the two may reach the same place by different
    // paths.
    public static func isFile(_ file: URL, inside folder: URL) -> Bool {
        let folderPath = folder.resolvingSymlinksInPath().standardizedFileURL.path
        return file.resolvingSymlinksInPath().standardizedFileURL.path.hasPrefix(folderPath.hasSuffix("/") ? folderPath : folderPath + "/")
    }

    // The file's scene under one node named after the file, detached from any scene graph. Animations are not kept.
    // A glTF root keeps the file and the buffers and images it loads as its modelSource, so a scene archive can store
    // the file instead of the subtree (#157).
    public static func load(_ url: URL, device: MTLDevice) throws -> (node: SceneGraph.Node, warnings: [String]) {
        let pathExtension = url.pathExtension.lowercased()
        let root: SceneGraph.Node
        let warnings: [String]
        if glTFExtensions.contains(pathExtension) {
            let result = try GLTFAsset(url: url, device: device).makeSceneGraph(device: device)
            root = result.sceneGraph.root
            warnings = result.warnings
            root.modelSource = try SceneGraph.ModelSource(url: url, relatedFiles: externalFiles(url))
        } else if modelIOExtensions.contains(pathExtension) {
            let result = try ModelIOSceneGraph(url: url, device: device)
            root = result.sceneGraph.root
            warnings = result.warnings
        } else {
            throw Failure.unsupportedFormat(pathExtension)
        }
        root.label = url.deletingPathExtension().lastPathComponent
        return (root, warnings)
    }
}

// Reads models kept by reference in a scene package (#157).
public struct ModelFileLoader: ArchivableModelLoader {
    public init() {}

    public func load(_ url: URL, context: SceneArchiveContext) throws -> (node: SceneGraph.Node, warnings: [String]) {
        try ModelFile.load(url, device: context.device)
    }
}
