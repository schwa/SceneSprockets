import Foundation
import Metal
import MetalSprocketsGLTF
import MetalSupport
import ModelIO
import SceneSprockets
import UniformTypeIdentifiers

/// Loads a model file of any supported format into one subtree, to insert into a scene.
///
/// glTF files (`.gltf`, `.glb`) load with SceneSprockets' glTF converter (PBR materials, animations, variants, image-based
/// light). The formats that Model I/O reads (`.usdz`, `.usd`, `.obj`, `.ply`, `.stl`, `.abc`) load with Model I/O.
/// Every format gives the same ``Result`` (#371).
public enum ModelFile {
    /// A loaded model.
    public struct Result {
        /// The model's root node, named after the file, not yet in a scene graph.
        public var node: SceneGraph.Node
        /// The model's animations, as clips that animate nodes under ``node``. Empty if nothing is animated.
        public var animations: [SceneGraph.AnimationClip]
        /// Messages about parts of the file that the conversion skipped or changed.
        public var warnings: [String]
        /// The glTF `KHR_materials_variants` variants, or nil when the file has none.
        public var variants: MaterialVariants?
        /// The glTF `EXT_lights_image_based` light, for `SceneGraph.environment.map`, or nil.
        public var environmentMap: (any EnvironmentMap)?
    }

    /// A glTF file's material variants. The model starts with the variant it was loaded with.
    public struct MaterialVariants {
        /// The variant names, in file order.
        public var names: [String]
        let gltf: GLTFImport

        /// Swaps every mesh's materials for variant `index` (into ``names``; nil for the default materials). Node
        /// state and animation players are kept. Throws for an out-of-range index.
        public func select(_ index: Int?) throws {
            try gltf.selectVariant(index)
        }
    }

    /// The kind of scene material that Model I/O formats get. glTF files always get ``PBRSceneMaterial``.
    public enum MaterialKind: Sendable {
        /// ``PBRSceneMaterial`` materials.
        case pbr
        /// Blinn-Phong materials.
        case blinnPhong
    }

    /// The file extensions that load with the glTF converter.
    public static let glTFExtensions: Set<String> = ["gltf", "glb"]
    /// The file extensions that load with Model I/O.
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

    /// Loads a model file of any supported format.
    ///
    /// The root node is named after the file. A glTF root keeps the file and the buffers and images it loads as its
    /// `modelSource`, so a scene archive can store the file instead of the subtree (#157).
    ///
    /// - Parameters:
    ///   - url: The file to load.
    ///   - materials: The kind of material for Model I/O formats. glTF files always get PBR materials.
    /// - Throws: ``Failure/unsupportedFormat(_:)`` for other extensions, or an error if loading or conversion fails.
    public static func load(_ url: URL, materials: MaterialKind = .pbr) throws -> Result {
        let pathExtension = url.pathExtension.lowercased()
        var result: Result
        if glTFExtensions.contains(pathExtension) {
            result = try load(GLTFAsset(url: url, device: _MTLCreateSystemDefaultDevice()))
            result.node.modelSource = try SceneGraph.ModelSource(url: url, relatedFiles: externalFiles(url))
        } else if modelIOExtensions.contains(pathExtension) {
            result = Result(modelIO: try ModelIOImport(url: url, materials: materials))
        } else {
            throw Failure.unsupportedFormat(pathExtension)
        }
        result.node.label = url.deletingPathExtension().lastPathComponent
        return result
    }

    /// Converts a glTF asset that is already loaded.
    public static func load(_ asset: GLTFAsset) throws -> Result {
        let gltf = try asset.importScene()
        return Result(
            node: gltf.sceneGraph.root,
            animations: gltf.animations,
            warnings: gltf.warnings,
            variants: gltf.variantNames.isEmpty ? nil : MaterialVariants(names: gltf.variantNames, gltf: gltf),
            environmentMap: gltf.sceneGraph.environment.map
        )
    }

    /// Converts a Model I/O asset that is already loaded.
    ///
    /// - Parameters:
    ///   - asset: The asset to convert.
    ///   - materials: The kind of scene material to make.
    ///   - label: The label of the root node.
    public static func load(_ asset: MDLAsset, materials: MaterialKind = .pbr, label: String? = nil) throws -> Result {
        Result(modelIO: try ModelIOImport(asset: asset, materials: materials, label: label))
    }
}

/// The loader that `Archive` uses for models that a scene package keeps by reference.
public struct ModelFileLoader: ArchivableModelLoader {
    /// Creates a model file loader.
    public init() {}

    public func load(_ url: URL, context _: ArchiveContext) throws -> (node: SceneGraph.Node, warnings: [String]) {
        let result = try ModelFile.load(url)
        return (result.node, result.warnings)
    }
}

extension ModelFile.Result {
    init(modelIO source: ModelIOImport) {
        self.init(node: source.sceneGraph.root, animations: source.animations, warnings: source.warnings, variants: nil, environmentMap: nil)
    }
}
