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
        guard url.pathExtension.lowercased() == "gltf" else {
            return false
        }
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any] ?? [:]
        let resources = (json["buffers"] as? [[String: Any]] ?? []) + (json["images"] as? [[String: Any]] ?? [])
        return resources.contains { resource in
            guard let uri = resource["uri"] as? String else {
                return false
            }
            return !uri.hasPrefix("data:")
        }
    }

    // Whether `file` is inside `folder`. Symlinks are resolved, because the two may reach the same place by different
    // paths.
    public static func isFile(_ file: URL, inside folder: URL) -> Bool {
        let folderPath = folder.resolvingSymlinksInPath().standardizedFileURL.path
        return file.resolvingSymlinksInPath().standardizedFileURL.path.hasPrefix(folderPath.hasSuffix("/") ? folderPath : folderPath + "/")
    }

    // The file's scene under one node named after the file, detached from any scene graph. Animations are not kept.
    public static func load(_ url: URL, device: MTLDevice) throws -> (node: SceneGraph.Node, warnings: [String]) {
        let pathExtension = url.pathExtension.lowercased()
        let root: SceneGraph.Node
        let warnings: [String]
        if glTFExtensions.contains(pathExtension) {
            let result = try GLTFAsset(url: url, device: device).makeSceneGraph(device: device)
            root = result.sceneGraph.root
            warnings = result.warnings
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
