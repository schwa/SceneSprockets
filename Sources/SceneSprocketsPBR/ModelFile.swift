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
