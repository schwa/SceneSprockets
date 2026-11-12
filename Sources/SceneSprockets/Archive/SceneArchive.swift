import CoreGraphics
import Foundation
import ImageIO
import Metal
import MetalSupport
import SwiftMesh
import UniformTypeIdentifiers

/// Saves and loads a scene graph as a package directory.
///
/// The package (`.scenesprocketsd`) holds `scene.json` for the graph and `textures/` for textures that the archive
/// reads back from the GPU. The core module does not know the renderer modules, so you give the archive the material
/// and environment map types that the scene uses.
public struct SceneArchive {
    /// The file extension of a scene package.
    public static let pathExtension = "scenesprocketsd"
    static let sceneFileName = "scene.json"
    static let texturesDirectoryName = "textures"
    static let formatVersion = 1

    /// The material types that the archive can save and load.
    public var materialTypes: [any ArchivableMaterial.Type]
    /// The environment map types that the archive can save and load.
    public var environmentMapTypes: [any ArchivableEnvironmentMap.Type]
    /// The codec that saves meshes that are not shapes, such as generated geometry.
    ///
    /// If it is `nil`, the archive skips these meshes and adds a warning.
    public var meshCodec: (any ArchivableMeshCodec)?
    /// The loader for model files that the package keeps by reference.
    ///
    /// The archive saves a node with a `modelSource` as a reference to its file only when it has a loader. Otherwise
    /// it saves the node's subtree like any other.
    public var modelLoader: (any ArchivableModelLoader)?
    /// The Metal libraries that saved shader materials refer to, by name.
    ///
    /// A compiled function does not record its library, so the app names the libraries that it uses.
    public var shaderLibraries: [String: any MTLLibrary]

    /// Creates an archive.
    ///
    /// - Parameters:
    ///   - materialTypes: The material types that the archive can save and load.
    ///   - environmentMapTypes: The environment map types that the archive can save and load.
    ///   - shaderLibraries: The Metal libraries that shader materials use, by name.
    ///   - meshCodec: The codec for meshes that are not shapes.
    ///   - modelLoader: The loader for model files that the package keeps by reference.
    public init(materialTypes: [any ArchivableMaterial.Type] = [], environmentMapTypes: [any ArchivableEnvironmentMap.Type] = [], shaderLibraries: [String: any MTLLibrary] = [:], meshCodec: (any ArchivableMeshCodec)? = nil, modelLoader: (any ArchivableModelLoader)? = nil) {
        self.materialTypes = materialTypes
        self.environmentMapTypes = environmentMapTypes
        self.shaderLibraries = shaderLibraries
        self.meshCodec = meshCodec
        self.modelLoader = modelLoader
    }

    /// Saves a scene graph as a package, and replaces anything at the URL.
    ///
    /// - Returns: Messages about parts of the scene that the archive could not save.
    /// - Throws: An error if encoding or writing fails.
    @discardableResult
    public func write(_ sceneGraph: SceneGraph, to url: URL) throws -> [String] {
        let capture = try capture(sceneGraph)
        try capture.write(to: url)
        return capture.warnings
    }

    /// Returns the contents of the package files as values, to write later.
    ///
    /// Call this method on the thread that owns the scene graph. Later edits do not change the capture, and you can
    /// write it on any thread.
    ///
    /// - Parameters:
    ///   - sceneGraph: The scene graph to save.
    ///   - textureCache: A cache that keeps texture bytes between captures, so that the archive reads each unchanged
    ///     texture from the GPU only once.
    /// - Throws: An error if encoding fails or a texture cannot be read.
    public func capture(_ sceneGraph: SceneGraph, textureCache: TextureCache? = nil) throws -> Capture {
        let context = SceneArchiveContext(directory: nil, archive: self)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        encoder.userInfo[.sceneArchive] = context
        // swiftlint:disable:next optional_data_string_conversion - JSONEncoder output is valid UTF-8
        let json = try String(decoding: encoder.encode(sceneGraph), as: UTF8.self)
        let cache = textureCache ?? TextureCache()
        var files = context.files
        for pending in context.pendingTextures {
            files[pending.file] = try cache.data(for: pending.texture, isPNG: pending.file.hasSuffix(".png"))
        }
        cache.keepOnly(context.pendingTextures.map(\.texture))
        return Capture(scene: Data(ArchiveFormatting.compactNumberArrays(json).utf8), files: files, warnings: context.warnings)
    }

    struct PendingTexture {
        let texture: any MTLTexture
        let file: String
    }

    /// A cache of texture file bytes for repeated captures.
    ///
    /// Textures do not change in place, so the bytes stay correct while the texture exists. Use a cache from one
    /// thread only.
    public final class TextureCache {
        private var entries: [ObjectIdentifier: (texture: any MTLTexture, isPNG: Bool, data: Data)] = [:]

        /// Creates an empty cache.
        public init() {}

        func data(for texture: any MTLTexture, isPNG: Bool) throws -> Data {
            if let entry = entries[ObjectIdentifier(texture)], entry.isPNG == isPNG {
                return entry.data
            }
            let data = try SceneArchiveContext.fileData(texture, isPNG: isPNG)
            entries[ObjectIdentifier(texture)] = (texture, isPNG, data)
            return data
        }

        // Drops textures the scene no longer uses.
        func keepOnly(_ textures: [any MTLTexture]) {
            let used = Set(textures.map(ObjectIdentifier.init))
            entries = entries.filter { used.contains($0.key) }
        }
    }

    /// The contents of a package's files, made by ``SceneArchive/capture(_:textureCache:)``.
    public struct Capture: Sendable {
        let scene: Data
        // Textures and mesh files by path in the package.
        let files: [String: Data]
        /// Messages about parts of the scene that the archive could not save.
        public let warnings: [String]

        /// Writes the package files, and replaces anything at the URL.
        ///
        /// - Throws: An error if a file cannot be written.
        public func write(to url: URL) throws {
            let fileManager = FileManager.default
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
            try scene.write(to: url.appendingPathComponent(SceneArchive.sceneFileName))
            for (file, data) in files {
                let fileURL = url.appendingPathComponent(file)
                try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: fileURL)
            }
        }
    }

    /// Loads a scene graph from a package.
    ///
    /// - Parameters:
    ///   - url: The package to read.
    /// - Returns: The scene graph, and messages about parts of the package that the archive could not load.
    /// - Throws: A ``SceneArchiveError``, or an error if a file cannot be read or decoded.
    public func read(from url: URL) throws -> (sceneGraph: SceneGraph, warnings: [String]) {
        let context = SceneArchiveContext(directory: url, archive: self)
        let decoder = JSONDecoder()
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        decoder.userInfo[.sceneArchive] = context
        let sceneGraph = try decoder.decode(SceneGraph.self, from: Data(contentsOf: url.appendingPathComponent(Self.sceneFileName)))
        return (sceneGraph, context.warnings)
    }
}

/// A loader for model files that a scene package keeps by reference, such as glTF files.
public protocol ArchivableModelLoader {
    /// Loads a model file.
    ///
    /// - Parameters:
    ///   - url: The model file.
    ///   - context: The archive context, for the device and warnings.
    /// - Returns: The file's subtree under one root node, and messages from the loader.
    func load(_ url: URL, context: SceneArchiveContext) throws -> (node: SceneGraph.Node, warnings: [String])
}

/// A codec that saves meshes that are not shapes as files in a scene package.
///
/// The exact materials stay in `scene.json`. A codec can also write materials into its file for other tools.
public protocol ArchivableMeshCodec {
    /// Adds a file for the mesh to the package and returns its path.
    ///
    /// - Parameters:
    ///   - mesh: The mesh to save.
    ///   - materials: The materials of the mesh's submeshes.
    ///   - name: A name for the mesh, for example the node label.
    ///   - context: The archive context. Use ``SceneArchiveContext/newFile(in:pathExtension:)`` and
    ///     ``SceneArchiveContext/addFile(_:data:)`` to add the file.
    /// - Returns: The path of the file in the package.
    func encode(_ mesh: MetalMesh, materials: [any SceneMaterial], name: String?, context: SceneArchiveContext) throws -> String
    /// Reads a mesh from a file in the package.
    ///
    /// - Parameters:
    ///   - path: The path that ``encode(_:materials:name:context:)`` returned.
    ///   - context: The archive context, for the device and the file.
    func decode(path: String, context: SceneArchiveContext) throws -> MetalMesh
}

/// A material that a scene archive can save and load.
///
/// The material encodes itself with `Codable`. It encodes textures through the ``SceneArchiveContext`` of the coder.
public protocol ArchivableMaterial: SceneMaterial, Codable {
    /// The name that identifies the material type in `scene.json`. It must be unique among the archive's types.
    static var archiveTypeName: String { get }
    /// Returns why the material cannot be saved, or `nil` if it can.
    ///
    /// The archive calls this method before it encodes the material. If there is a reason, the archive skips the
    /// material and adds a warning, instead of failing. The default implementation returns `nil`.
    func archiveProblem(context: SceneArchiveContext) -> String?
}

public extension ArchivableMaterial {
    /// Returns `nil`: the material can always be saved.
    func archiveProblem(context _: SceneArchiveContext) -> String? {
        nil
    }
}

/// An environment map that a scene archive can save and load.
///
/// Environment maps are classes, so decoding is a static function instead of an initializer.
public protocol ArchivableEnvironmentMap: EnvironmentMap {
    /// The name that identifies the map type in `scene.json`. It must be unique among the archive's types.
    static var archiveTypeName: String { get }
    /// Encodes the map. Encode textures through the coder's ``SceneArchiveContext``.
    func encode(to encoder: Encoder) throws
    /// Decodes a map that ``encode(to:)`` encoded.
    static func decodeEnvironmentMap(from decoder: Decoder) throws -> any EnvironmentMap
}

/// Errors from saving or loading a scene archive.
public enum SceneArchiveError: Error, CustomStringConvertible {
    /// The coder has no ``SceneArchiveContext``. Encode and decode scene graphs through ``SceneArchive``.
    case missingContext
    /// Reading needs the package directory, and there is none.
    case missingDirectory
    /// The archive cannot save the texture. The value gives the reason.
    case unsupportedTexture(String)
    /// The texture file cannot be read. The value is the file name.
    case unreadableTexture(String)
    /// The archive cannot save or read the mesh. The value gives the reason.
    case unsupportedMesh(String)
    /// The package has a newer format version than this code can read.
    case unsupportedFormatVersion(Int)

    public var description: String {
        switch self {
        case .missingContext: "Coding a scene graph needs a SceneArchive"
        case .missingDirectory: "Reading a scene archive needs its directory"
        case .unsupportedTexture(let reason): "Unsupported texture: \(reason)"
        case .unreadableTexture(let name): "Could not read texture \(name)"
        case .unsupportedMesh(let reason): "Cannot save or read the mesh: \(reason)"
        case .unsupportedFormatVersion(let version): "Scene archive format \(version) is newer than this code (\(SceneArchive.formatVersion))"
        }
    }
}

public extension CodingUserInfoKey {
    /// The key for the ``SceneArchiveContext`` in a coder's user info.
    static let sceneArchive = CodingUserInfoKey(rawValue: "io.schwa.SceneSprockets.sceneArchive")! // swiftlint:disable:this force_unwrapping
}

public extension Encoder {
    /// The archive context of the encoder.
    ///
    /// - Throws: ``SceneArchiveError/missingContext`` if the encoder is not encoding a scene archive.
    var sceneArchive: SceneArchiveContext {
        get throws {
            try (userInfo[.sceneArchive] as? SceneArchiveContext).orThrow(SceneArchiveError.missingContext)
        }
    }
}

public extension Decoder {
    /// The archive context of the decoder.
    ///
    /// - Throws: ``SceneArchiveError/missingContext`` if the decoder is not decoding a scene archive.
    var sceneArchive: SceneArchiveContext {
        get throws {
            try (userInfo[.sceneArchive] as? SceneArchiveContext).orThrow(SceneArchiveError.missingContext)
        }
    }
}

private extension Optional {
    func orThrow(_ error: some Error) throws -> Wrapped {
        guard let self else {
            throw error
        }
        return self
    }
}

/// The state that everything coded in one archive shares.
///
/// The context holds the archive's types, the textures that are already written or read, the package files, and the
/// warnings. Materials and other coded values get it from their coder's ``Swift/Encoder/sceneArchive`` or
/// ``Swift/Decoder/sceneArchive``. A context exists for one write or read, on one thread.
public final class SceneArchiveContext: @unchecked Sendable {
    // Where to read from; nil while capturing, which only encodes.
    let directory: URL?
    let archive: SceneArchive
    /// Messages about parts of the scene that the archive skipped or changed.
    public private(set) var warnings: [String] = []
    private var writtenTextures: [ObjectIdentifier: TextureReference] = [:]
    // Textures named while encoding, written after (#238).
    var pendingTextures: [SceneArchive.PendingTexture] = []
    // Other files to write, such as meshes (#158), by path in the package.
    private(set) var files: [String: Data] = [:]

    /// Returns a new file path in the package, `directory/N.pathExtension`, with the next free number.
    public func newFile(in directory: String, pathExtension: String) -> String {
        "\(directory)/\(files.keys.count { $0.hasPrefix(directory + "/") }).\(pathExtension)"
    }

    /// Adds a file to the package at a path.
    public func addFile(_ path: String, data: Data) {
        files[path] = data
    }

    /// Returns the contents of a file in the package that the archive reads.
    ///
    /// - Throws: An error if the file cannot be read, or if the context is not reading.
    public func data(atPath path: String) throws -> Data {
        try Data(contentsOf: readDirectory.appendingPathComponent(path))
    }

    /// Returns the URL of a file in the package that the archive reads.
    ///
    /// - Throws: An error if the context is not reading.
    public func url(forPath path: String) throws -> URL {
        try readDirectory.appendingPathComponent(path)
    }

    /// The archive's mesh codec, if any.
    public var meshCodec: (any ArchivableMeshCodec)? {
        archive.meshCodec
    }

    // Files already written for meshes, by the identity of their GPU buffers; and meshes already read, by file.
    var meshFiles: [[ObjectIdentifier]: String] = [:]
    var decodedMeshes: [String: MetalMesh] = [:]
    // Audio files already written, by the identity of their buffers (#182).
    var audioFiles: [ObjectIdentifier: String] = [:]
    // Model files already copied into the package, by source, so shared ones are written once.
    var modelFiles: [SceneGraph.ModelSource: String] = [:]

    /// The archive's model loader, if any.
    public var modelLoader: (any ArchivableModelLoader)? {
        archive.modelLoader
    }

    // Copies `source` into its own folder under models/ and returns the main file's path.
    func addModel(_ source: SceneGraph.ModelSource) -> String {
        if let path = modelFiles[source] {
            return path
        }
        let folder = "models/\(modelFiles.count)"
        for (path, data) in source.files {
            addFile("\(folder)/\(path)", data: data)
        }
        let path = "\(folder)/\(source.mainFile)"
        modelFiles[source] = path
        return path
    }

    // The model at `path` in the package, with every file in its folder.
    func modelSource(atPath path: String) throws -> SceneGraph.ModelSource {
        let main = try url(forPath: path)
        let folder = main.deletingLastPathComponent()
        var files: [String: Data] = [:]
        let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey])
        while let file = enumerator?.nextObject() as? URL {
            guard try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
                continue
            }
            let relative = String(file.standardizedFileURL.path.dropFirst(folder.standardizedFileURL.path.count + 1))
            files[relative] = try Data(contentsOf: file)
        }
        return SceneGraph.ModelSource(mainFile: main.lastPathComponent, files: files)
    }

    func meshKey(_ mesh: MetalMesh) -> [ObjectIdentifier] {
        mesh.vertexBuffers.sorted { $0.key < $1.key }.map { ObjectIdentifier($0.value) } + mesh.submeshes.map { ObjectIdentifier($0.indexBuffer) }
    }
    private var readTextures: [String: MTLTexture] = [:]
    // Constraints refer to nodes by path from this root.
    var encodingRoot: SceneGraph.Node?
    // Constraints read with their nodes, resolved once the whole tree is read.
    var pendingConstraints: [(node: SceneGraph.Node, constraints: [ArchivedConstraint])] = []
    var pendingSkins: [(node: SceneGraph.Node, skin: ArchivedSkin)] = []

    init(directory: URL?, archive: SceneArchive) {
        self.directory = directory
        self.archive = archive
    }

    // Reading has a directory; capturing has none.
    private var readDirectory: URL {
        get throws {
            try directory.orThrow(SceneArchiveError.missingDirectory)
        }
    }

    func resolveConstraints(root: SceneGraph.Node) {
        for (node, constraints) in pendingConstraints {
            node.constraints = constraints.compactMap { archived in
                guard let constraint = archived.constraint(root: root) else {
                    warn("\(node.label ?? "node"): constraint refers to a missing node; skipped")
                    return nil
                }
                return constraint
            }
        }
        pendingConstraints = []
    }

    /// Returns the name of a shader library in ``SceneArchive/shaderLibraries``, or `nil` if the archive does not
    /// have it.
    public func shaderLibraryName(for library: any MTLLibrary) -> String? {
        archive.shaderLibraries.first { $0.value === library }?.key
    }

    /// Returns the shader library with a name in ``SceneArchive/shaderLibraries``, or `nil` if there is none.
    public func shaderLibrary(named name: String) -> (any MTLLibrary)? {
        archive.shaderLibraries[name]
    }

    /// Adds a message to ``warnings``.
    public func warn(_ message: String) {
        warnings.append(message)
    }

    func materialType(named name: String) -> (any ArchivableMaterial.Type)? {
        archive.materialTypes.first { $0.archiveTypeName == name }
    }

    func environmentMapType(named name: String) -> (any ArchivableEnvironmentMap.Type)? {
        archive.environmentMapTypes.first { $0.archiveTypeName == name }
    }

    // MARK: Textures

    /// The location of a texture in the package, and the properties to rebuild it with.
    public struct TextureReference: Codable, Equatable, Sendable {
        /// The path of the texture file in the package.
        public var file: String
        /// The raw value of the `MTLPixelFormat`.
        public var pixelFormat: UInt
        /// The width, in pixels.
        public var width: Int
        /// The height, in pixels.
        public var height: Int
        /// Whether the texture has mipmaps.
        public var mipmapped: Bool
        /// The texture type of a `.bin` file: `nil` for 2D, or `"2DArray"`, `"cube"`, `"cubeArray"` or `"3D"`.
        public var type: String?
        /// The depth of a 3D texture.
        public var depth: Int?
        /// The number of slices of an array texture.
        public var arrayLength: Int?
        /// The number of mip levels in the file, for every slice in turn.
        ///
        /// If it is `nil`, the file has only level 0, and the archive generates the other levels.
        public var levels: Int?
    }

    /// The filters and address modes of a sampler, saved from the `MTLSamplerDescriptor` that a material keeps.
    public struct SamplerReference: Codable, Equatable, Sendable {
        /// The minification filter.
        public var minFilter: String
        /// The magnification filter.
        public var magFilter: String
        /// The mipmap filter.
        public var mipFilter: String
        /// The address mode for the s (u) coordinate.
        public var sAddressMode: String
        /// The address mode for the t (v) coordinate.
        public var tAddressMode: String
        /// The address mode for the r coordinate.
        public var rAddressMode: String
        /// The maximum anisotropy.
        public var maxAnisotropy: Int

        /// Creates a reference from a sampler descriptor.
        public init(_ descriptor: MTLSamplerDescriptor) {
            minFilter = Self.name(descriptor.minFilter)
            magFilter = Self.name(descriptor.magFilter)
            mipFilter = Self.name(descriptor.mipFilter)
            sAddressMode = Self.name(descriptor.sAddressMode)
            tAddressMode = Self.name(descriptor.tAddressMode)
            rAddressMode = Self.name(descriptor.rAddressMode)
            maxAnisotropy = descriptor.maxAnisotropy
        }

        /// A new sampler descriptor with these filters and address modes.
        public var descriptor: MTLSamplerDescriptor {
            let descriptor = MTLSamplerDescriptor()
            descriptor.minFilter = minFilter == "nearest" ? .nearest : .linear
            descriptor.magFilter = magFilter == "nearest" ? .nearest : .linear
            descriptor.mipFilter = switch mipFilter {
            case "nearest": .nearest
            case "linear": .linear
            default: .notMipmapped
            }
            descriptor.sAddressMode = Self.addressMode(sAddressMode)
            descriptor.tAddressMode = Self.addressMode(tAddressMode)
            descriptor.rAddressMode = Self.addressMode(rAddressMode)
            descriptor.maxAnisotropy = max(maxAnisotropy, 1)
            return descriptor
        }

        private static func name(_ filter: MTLSamplerMinMagFilter) -> String {
            filter == .nearest ? "nearest" : "linear"
        }

        private static func name(_ filter: MTLSamplerMipFilter) -> String {
            switch filter {
            case .nearest: "nearest"
            case .linear: "linear"
            default: "none"
            }
        }

        private static let addressModes: [(String, MTLSamplerAddressMode)] = [
            ("clampToEdge", .clampToEdge), ("mirrorClampToEdge", .mirrorClampToEdge), ("repeat", .repeat),
            ("mirrorRepeat", .mirrorRepeat), ("clampToZero", .clampToZero), ("clampToBorderColor", .clampToBorderColor)
        ]

        private static func name(_ mode: MTLSamplerAddressMode) -> String {
            addressModes.first { $0.1 == mode }?.0 ?? "clampToEdge"
        }

        private static func addressMode(_ name: String) -> MTLSamplerAddressMode {
            addressModes.first { $0.0 == name }?.1 ?? .clampToEdge
        }
    }

    /// Reads `texture` back from the GPU and writes it once per archive. 2D 8-bit RGBA and BGRA textures are a PNG of
    /// level 0 (mips are regenerated on load); everything else is raw bytes of every slice and mip level.
    /// Names the texture's file. The bytes are written now, or by SceneArchive.Capture.write when capturing (#238).
    public func encode(texture: MTLTexture) throws -> TextureReference {
        if let reference = writtenTextures[ObjectIdentifier(texture)] {
            return reference
        }
        guard let typeName = Self.textureTypeNames.first(where: { $0.value == texture.textureType })?.key else {
            throw SceneArchiveError.unsupportedTexture("type \(texture.textureType.rawValue)")
        }
        guard TextureLayout(texture.pixelFormat) != nil else {
            throw SceneArchiveError.unsupportedTexture("pixel format \(texture.pixelFormat.rawValue)")
        }
        let index = writtenTextures.count
        let isPNG = texture.textureType == .type2D && Self.pngFormats.contains(texture.pixelFormat)
        let reference = if isPNG {
            TextureReference(file: "\(SceneArchive.texturesDirectoryName)/\(index).png", pixelFormat: texture.pixelFormat.rawValue, width: texture.width, height: texture.height, mipmapped: texture.mipmapLevelCount > 1)
        } else {
            TextureReference(
                file: "\(SceneArchive.texturesDirectoryName)/\(index).bin",
                pixelFormat: texture.pixelFormat.rawValue,
                width: texture.width,
                height: texture.height,
                mipmapped: texture.mipmapLevelCount > 1,
                type: typeName == "2D" ? nil : typeName,
                depth: texture.textureType == .type3D ? texture.depth : nil,
                arrayLength: [.type2DArray, .typeCubeArray].contains(texture.textureType) ? texture.arrayLength : nil,
                levels: texture.mipmapLevelCount
            )
        }
        writtenTextures[ObjectIdentifier(texture)] = reference
        pendingTextures.append(SceneArchive.PendingTexture(texture: texture, file: reference.file))
        return reference
    }

    // The texture's file contents, read back from the GPU: PNG data, or raw texels of every slice and level.
    static func fileData(_ texture: MTLTexture, isPNG: Bool) throws -> Data {
        guard let layout = TextureLayout(texture.pixelFormat) else {
            throw SceneArchiveError.unsupportedTexture("pixel format \(texture.pixelFormat.rawValue)")
        }
        guard isPNG else {
            var bytes: [UInt8] = []
            for slice in 0 ..< sliceCount(texture.textureType, arrayLength: texture.arrayLength) {
                for level in 0 ..< texture.mipmapLevelCount {
                    bytes += try readBack(texture, level: level, slice: slice, layout: layout)
                }
            }
            return Data(bytes)
        }
        var bytes = try readBack(texture, level: 0, slice: 0, layout: layout)
        if [.bgra8Unorm, .bgra8Unorm_srgb].contains(texture.pixelFormat) {
            for pixel in stride(from: 0, to: bytes.count, by: 4) {
                bytes.swapAt(pixel, pixel + 2)
            }
        }
        return try pngData(bytes: bytes, width: texture.width, height: texture.height)
    }

    /// The stored file's bytes: PNG data, or raw rows of `pixelFormat` texels.
    public func data(for reference: TextureReference) throws -> Data {
        try Data(contentsOf: readDirectory.appendingPathComponent(reference.file))
    }

    /// Returns the texture for a reference, and reads it from the package the first time.
    ///
    /// - Throws: ``SceneArchiveError/unreadableTexture(_:)`` if the file does not match the reference, or an error if
    ///   it cannot be read.
    public func texture(for reference: TextureReference) throws -> MTLTexture {
        if let texture = readTextures[reference.file] {
            return texture
        }
        let device = _MTLCreateSystemDefaultDevice()
        let url = try readDirectory.appendingPathComponent(reference.file)
        let pixelFormat = MTLPixelFormat(rawValue: reference.pixelFormat) ?? .rgba8Unorm
        guard let layout = TextureLayout(pixelFormat) else {
            throw SceneArchiveError.unsupportedTexture("pixel format \(reference.pixelFormat)")
        }
        guard let textureType = Self.textureTypeNames[reference.type ?? "2D"] else {
            throw SceneArchiveError.unsupportedTexture("type \(reference.type ?? "")")
        }
        if let levels = reference.levels {
            return try readRawTexture(reference, pixelFormat: pixelFormat, textureType: textureType, levels: levels, layout: layout)
        }
        let bytesPerPixel = layout.bytesPerBlock
        // The recorded pixel format, so a texture saves back unchanged.
        var bytes: [UInt8]
        if url.pathExtension == "png" {
            bytes = try Self.readPNG(url, width: reference.width, height: reference.height)
            if [.bgra8Unorm, .bgra8Unorm_srgb].contains(pixelFormat) {
                for pixel in stride(from: 0, to: bytes.count, by: 4) {
                    bytes.swapAt(pixel, pixel + 2)
                }
            }
        } else {
            bytes = [UInt8](try Data(contentsOf: url))
        }
        guard bytes.count == reference.width * reference.height * bytesPerPixel else {
            throw SceneArchiveError.unreadableTexture(reference.file)
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: pixelFormat, width: reference.width, height: reference.height, mipmapped: reference.mipmapped)
        descriptor.usage = .shaderRead
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw SceneArchiveError.unreadableTexture(reference.file)
        }
        texture.replace(region: MTLRegionMake2D(0, 0, reference.width, reference.height), mipmapLevel: 0, withBytes: bytes, bytesPerRow: reference.width * bytesPerPixel)
        if reference.mipmapped {
            try Self.generateMipmaps(texture)
        }
        texture.label = reference.file
        readTextures[reference.file] = texture
        return texture
    }

    private static let pngFormats: Set<MTLPixelFormat> = [.rgba8Unorm, .rgba8Unorm_srgb, .bgra8Unorm, .bgra8Unorm_srgb]

    private static let textureTypeNames: [String: MTLTextureType] = ["2D": .type2D, "2DArray": .type2DArray, "cube": .typeCube, "cubeArray": .typeCubeArray, "3D": .type3D]

    private static func sliceCount(_ type: MTLTextureType, arrayLength: Int) -> Int {
        switch type {
        case .type2DArray: arrayLength
        case .typeCube: 6
        case .typeCubeArray: 6 * arrayLength
        default: 1
        }
    }

    // Bytes per block of texels: 1x1 for plain formats, 4x4 and larger for compressed ones.
    struct TextureLayout {
        var blockWidth = 1
        var blockHeight = 1
        var bytesPerBlock: Int

        init?(_ format: MTLPixelFormat) {
            switch format {
            case .r8Unorm: bytesPerBlock = 1
            case .rg8Unorm, .r16Float: bytesPerBlock = 2
            case .rgba8Unorm, .rgba8Unorm_srgb, .bgra8Unorm, .bgra8Unorm_srgb, .r32Float, .rg16Float: bytesPerBlock = 4
            case .rgba16Float, .rg32Float: bytesPerBlock = 8
            case .rgba32Float: bytesPerBlock = 16
            case .bc1_rgba, .bc1_rgba_srgb, .bc4_rUnorm, .bc4_rSnorm:
                (blockWidth, blockHeight, bytesPerBlock) = (4, 4, 8)
            case .bc2_rgba, .bc2_rgba_srgb, .bc3_rgba, .bc3_rgba_srgb, .bc5_rgUnorm, .bc5_rgSnorm, .bc6H_rgbFloat, .bc6H_rgbuFloat, .bc7_rgbaUnorm, .bc7_rgbaUnorm_srgb,
                 .astc_4x4_ldr, .astc_4x4_srgb, .astc_4x4_hdr: // swiftlint:disable:this indentation_width
                (blockWidth, blockHeight, bytesPerBlock) = (4, 4, 16)
            case .astc_5x5_ldr, .astc_5x5_srgb, .astc_5x5_hdr:
                (blockWidth, blockHeight, bytesPerBlock) = (5, 5, 16)
            case .astc_6x6_ldr, .astc_6x6_srgb, .astc_6x6_hdr:
                (blockWidth, blockHeight, bytesPerBlock) = (6, 6, 16)
            case .astc_8x8_ldr, .astc_8x8_srgb, .astc_8x8_hdr:
                (blockWidth, blockHeight, bytesPerBlock) = (8, 8, 16)
            default: return nil
            }
        }

        // One mip level of one slice.
        func size(of texture: (width: Int, height: Int, depth: Int), level: Int) -> (region: MTLRegion, bytesPerRow: Int, bytesPerImage: Int, count: Int) {
            let width = max(texture.width >> level, 1)
            let height = max(texture.height >> level, 1)
            let depth = max(texture.depth >> level, 1)
            let bytesPerRow = (width + blockWidth - 1) / blockWidth * bytesPerBlock
            let bytesPerImage = bytesPerRow * ((height + blockHeight - 1) / blockHeight)
            return (MTLRegionMake3D(0, 0, 0, width, height, depth), bytesPerRow, bytesPerImage, bytesPerImage * depth)
        }
    }

    private func readRawTexture(_ reference: TextureReference, pixelFormat: MTLPixelFormat, textureType: MTLTextureType, levels: Int, layout: TextureLayout) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = textureType
        descriptor.pixelFormat = pixelFormat
        descriptor.width = reference.width
        descriptor.height = reference.height
        descriptor.depth = reference.depth ?? 1
        descriptor.arrayLength = reference.arrayLength ?? 1
        descriptor.mipmapLevelCount = max(levels, 1)
        descriptor.usage = .shaderRead
        descriptor.storageMode = .shared
        let device = _MTLCreateSystemDefaultDevice()
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw SceneArchiveError.unreadableTexture(reference.file)
        }
        let bytes = try data(for: reference)
        var offset = 0
        for slice in 0 ..< Self.sliceCount(textureType, arrayLength: descriptor.arrayLength) {
            for level in 0 ..< descriptor.mipmapLevelCount {
                let size = layout.size(of: (texture.width, texture.height, texture.depth), level: level)
                guard offset + size.count <= bytes.count else {
                    throw SceneArchiveError.unreadableTexture(reference.file)
                }
                bytes.withUnsafeBytes { buffer in
                    guard let baseAddress = buffer.baseAddress else {
                        return
                    }
                    texture.replace(region: size.region, mipmapLevel: level, slice: slice, withBytes: baseAddress + offset, bytesPerRow: size.bytesPerRow, bytesPerImage: size.bytesPerImage)
                }
                offset += size.count
            }
        }
        guard offset == bytes.count else {
            throw SceneArchiveError.unreadableTexture(reference.file)
        }
        texture.label = reference.file
        readTextures[reference.file] = texture
        return texture
    }

    // One mip level of one slice; copied through a shared buffer when the texture is not CPU readable.
    private static func readBack(_ texture: MTLTexture, level: Int, slice: Int, layout: TextureLayout) throws -> [UInt8] {
        let size = layout.size(of: (texture.width, texture.height, texture.depth), level: level)
        var bytes = [UInt8](repeating: 0, count: size.count)
        if texture.storageMode == .shared {
            texture.getBytes(&bytes, bytesPerRow: size.bytesPerRow, bytesPerImage: size.bytesPerImage, from: size.region, mipmapLevel: level, slice: slice)
            return bytes
        }
        let device = texture.device
        guard let buffer = device.makeBuffer(length: bytes.count, options: .storageModeShared),
              let queue = device.makeCommandQueue(),
              let commandBuffer = queue.makeCommandBuffer(),
              let blit = commandBuffer.makeBlitCommandEncoder()
        else {
            throw SceneArchiveError.unsupportedTexture("could not read back \(texture.label ?? "texture")")
        }
        blit.copy(from: texture, sourceSlice: slice, sourceLevel: level, sourceOrigin: MTLOrigin(), sourceSize: size.region.size, to: buffer, destinationOffset: 0, destinationBytesPerRow: size.bytesPerRow, destinationBytesPerImage: size.bytesPerImage)
        blit.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        bytes.withUnsafeMutableBytes { destination in
            destination.copyMemory(from: UnsafeRawBufferPointer(start: buffer.contents(), count: destination.count))
        }
        return bytes
    }

    private static func generateMipmaps(_ texture: MTLTexture) throws {
        guard let queue = texture.device.makeCommandQueue(), let commandBuffer = queue.makeCommandBuffer(), let blit = commandBuffer.makeBlitCommandEncoder() else {
            throw SceneArchiveError.unreadableTexture(texture.label ?? "texture")
        }
        blit.generateMipmaps(for: texture)
        blit.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }

    // RGBA bytes. PNGs written by `writePNG` decode as straight RGBA and are copied as is; other layouts are drawn,
    // which premultiplies alpha.
    private static func readPNG(_ url: URL, width: Int, height: Int) throws -> [UInt8] {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil), image.width == width, image.height == height else {
            throw SceneArchiveError.unreadableTexture(url.lastPathComponent)
        }
        let isStraightRGBA = image.bitsPerComponent == 8 && image.bitsPerPixel == 32 && image.alphaInfo == .last && image.bitmapInfo.isDisjoint(with: .byteOrderMask)
        if isStraightRGBA, let data = image.dataProvider?.data as Data? {
            var bytes = [UInt8](repeating: 0, count: width * height * 4)
            for row in 0 ..< height {
                let start = row * image.bytesPerRow
                bytes.replaceSubrange(row * width * 4 ..< (row + 1) * width * 4, with: data[start ..< start + width * 4])
            }
            return bytes
        }
        // swiftlint:disable:next force_unwrapping - the sRGB color space always exists
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw SceneArchiveError.unreadableTexture(url.lastPathComponent)
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return [UInt8](UnsafeRawBufferPointer(start: context.data, count: width * height * 4))
    }

    // Straight (not premultiplied) RGBA, so alpha round-trips exactly.
    private static func pngData(bytes: [UInt8], width: Int, height: Int) throws -> Data {
        let data = NSMutableData()
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              // swiftlint:disable:next force_unwrapping - the sRGB color space always exists
              let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent),
              let destination = CGImageDestinationCreateWithData(data as CFMutableData, UTType.png.identifier as CFString, 1, nil)
        else {
            throw SceneArchiveError.unsupportedTexture("could not encode PNG")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw SceneArchiveError.unsupportedTexture("could not encode PNG")
        }
        return data as Data
    }
}
