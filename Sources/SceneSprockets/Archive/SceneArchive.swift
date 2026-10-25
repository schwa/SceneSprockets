import CoreGraphics
import Foundation
import ImageIO
import Metal
import UniformTypeIdentifiers

// Saves and loads a scene graph as a package directory (`.scenesprocketsd`): `scene.json` for the graph, and
// `textures/` for textures read back from the GPU. Material and environment map types register themselves, because
// the core module does not know the renderer modules (#52, #156).
public struct SceneArchive {
    public static let pathExtension = "scenesprocketsd"
    static let sceneFileName = "scene.json"
    static let texturesDirectoryName = "textures"
    static let formatVersion = 1

    public var materialTypes: [any ArchivableMaterial.Type]
    public var environmentMapTypes: [any ArchivableEnvironmentMap.Type]
    // Metal libraries that saved shaders (ShaderMaterial) refer to by name. A compiled function does not say where
    // its library came from, so the app names the libraries it uses.
    public var shaderLibraries: [String: any MTLLibrary]

    public init(materialTypes: [any ArchivableMaterial.Type] = [], environmentMapTypes: [any ArchivableEnvironmentMap.Type] = [], shaderLibraries: [String: any MTLLibrary] = [:]) {
        self.materialTypes = materialTypes
        self.environmentMapTypes = environmentMapTypes
        self.shaderLibraries = shaderLibraries
    }

    // Replaces anything at `url`. Returns warnings for what could not be saved.
    @discardableResult
    public func write(_ sceneGraph: SceneGraph, to url: URL) throws -> [String] {
        let capture = try capture(sceneGraph)
        try capture.write(to: url)
        return capture.warnings
    }

    // Everything the archive's files hold, as values. Read the graph on the thread that owns it; later edits do not
    // change the capture, and it can be written on any thread (#238). `textureCache` keeps texture bytes between
    // captures, so unchanged textures are read back from the GPU once.
    public func capture(_ sceneGraph: SceneGraph, textureCache: TextureCache? = nil) throws -> Capture {
        let context = SceneArchiveContext(directory: nil, device: nil, archive: self)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        encoder.userInfo[.sceneArchive] = context
        let json = try String(decoding: encoder.encode(sceneGraph), as: UTF8.self)
        let cache = textureCache ?? TextureCache()
        var textures: [String: Data] = [:]
        for pending in context.pendingTextures {
            textures[pending.file] = try cache.data(for: pending.texture, isPNG: pending.file.hasSuffix(".png"))
        }
        cache.keepOnly(context.pendingTextures.map(\.texture))
        return Capture(scene: Data(ArchiveFormatting.compactNumberArrays(json).utf8), textures: textures, warnings: context.warnings)
    }

    struct PendingTexture {
        let texture: any MTLTexture
        let file: String
    }

    // Texture file bytes by texture. Textures are not edited in place, so the bytes stay valid while the texture
    // lives. Use from one thread.
    public final class TextureCache {
        private var entries: [ObjectIdentifier: (texture: any MTLTexture, isPNG: Bool, data: Data)] = [:]

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

    public struct Capture: Sendable {
        let scene: Data
        let textures: [String: Data]
        public let warnings: [String]

        // Replaces anything at `url`.
        public func write(to url: URL) throws {
            let fileManager = FileManager.default
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
            try scene.write(to: url.appendingPathComponent(SceneArchive.sceneFileName))
            for (file, data) in textures {
                let fileURL = url.appendingPathComponent(file)
                try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: fileURL)
            }
        }
    }

    public func read(from url: URL, device: MTLDevice) throws -> (sceneGraph: SceneGraph, warnings: [String]) {
        let context = SceneArchiveContext(directory: url, device: device, archive: self)
        let decoder = JSONDecoder()
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        decoder.userInfo[.sceneArchive] = context
        let sceneGraph = try decoder.decode(SceneGraph.self, from: Data(contentsOf: url.appendingPathComponent(Self.sceneFileName)))
        return (sceneGraph, context.warnings)
    }
}

// A material that can be saved: it encodes itself, textures through `SceneArchiveContext`.
public protocol ArchivableMaterial: Material, Codable {
    // Stored in scene.json to find the type again; unique among registered types.
    static var archiveTypeName: String { get }
    // Why this material cannot be saved with `context`, or nil. Checked before encoding; a reason skips the material
    // with a warning instead of failing the whole archive.
    func archiveProblem(context: SceneArchiveContext) -> String?
}

public extension ArchivableMaterial {
    func archiveProblem(context: SceneArchiveContext) -> String? {
        nil
    }
}

// An environment map that can be saved. Environment maps are classes, so decoding is a static function.
public protocol ArchivableEnvironmentMap: EnvironmentMap {
    static var archiveTypeName: String { get }
    func encode(to encoder: Encoder) throws
    static func decodeEnvironmentMap(from decoder: Decoder) throws -> any EnvironmentMap
}

public enum SceneArchiveError: Error, CustomStringConvertible {
    case missingContext
    case missingDevice
    case unsupportedTexture(String)
    case unreadableTexture(String)
    case unsupportedFormatVersion(Int)

    public var description: String {
        switch self {
        case .missingContext: "Coding a scene graph needs a SceneArchive"
        case .missingDevice: "Reading a scene archive needs a device"
        case .unsupportedTexture(let reason): "Unsupported texture: \(reason)"
        case .unreadableTexture(let name): "Could not read texture \(name)"
        case .unsupportedFormatVersion(let version): "Scene archive format \(version) is newer than this code (\(SceneArchive.formatVersion))"
        }
    }
}

public extension CodingUserInfoKey {
    static let sceneArchive = CodingUserInfoKey(rawValue: "io.schwa.SceneSprockets.sceneArchive")!
}

public extension Encoder {
    var sceneArchive: SceneArchiveContext {
        get throws {
            try (userInfo[.sceneArchive] as? SceneArchiveContext).orThrow(SceneArchiveError.missingContext)
        }
    }
}

public extension Decoder {
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

// State shared by everything coded in one archive: the registered types, textures already written or read, and
// warnings. Unchecked Sendable: coder userInfo values must be Sendable, but a context lives for one write or read on
// one thread.
public final class SceneArchiveContext: @unchecked Sendable {
    // Where to read from; nil while capturing, which only encodes.
    let directory: URL?
    let archive: SceneArchive
    private let readDevice: MTLDevice?
    public private(set) var warnings: [String] = []
    private var writtenTextures: [ObjectIdentifier: TextureReference] = [:]
    // Textures named while encoding, written after (#238).
    var pendingTextures: [SceneArchive.PendingTexture] = []
    private var readTextures: [String: MTLTexture] = [:]
    // Constraints refer to nodes by path from this root.
    var encodingRoot: SceneGraph.Node?
    // Constraints read with their nodes, resolved once the whole tree is read.
    var pendingConstraints: [(node: SceneGraph.Node, constraints: [ArchivedConstraint])] = []
    var pendingSkins: [(node: SceneGraph.Node, skin: ArchivedSkin)] = []

    init(directory: URL?, device: MTLDevice?, archive: SceneArchive) {
        self.directory = directory
        self.readDevice = device
        self.archive = archive
    }

    public var device: MTLDevice {
        get throws {
            try readDevice.orThrow(SceneArchiveError.missingDevice)
        }
    }

    // Reading has both a directory and a device; capturing has neither.
    private var readDirectory: URL {
        get throws {
            try directory.orThrow(SceneArchiveError.missingDevice)
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

    public func shaderLibraryName(for library: any MTLLibrary) -> String? {
        archive.shaderLibraries.first { $0.value === library }?.key
    }

    public func shaderLibrary(named name: String) -> (any MTLLibrary)? {
        archive.shaderLibraries[name]
    }

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

    // Where a texture is stored in the package, and what to rebuild it as.
    public struct TextureReference: Codable, Equatable, Sendable {
        public var file: String
        // MTLPixelFormat raw value.
        public var pixelFormat: UInt
        public var width: Int
        public var height: Int
        public var mipmapped: Bool
        // Only in .bin files (#180): nil for 2D, otherwise "2DArray", "cube", "cubeArray" or "3D".
        public var type: String?
        public var depth: Int?
        public var arrayLength: Int?
        // Mip levels stored in the file, every slice's levels in turn. Nil stores level 0 and regenerates the rest.
        public var levels: Int?
    }

    // A sampler's filters and address modes (#180), from the MTLSamplerDescriptor a material keeps.
    public struct SamplerReference: Codable, Equatable, Sendable {
        public var minFilter: String
        public var magFilter: String
        public var mipFilter: String
        public var sAddressMode: String
        public var tAddressMode: String
        public var rAddressMode: String
        public var maxAnisotropy: Int

        public init(_ descriptor: MTLSamplerDescriptor) {
            minFilter = Self.name(descriptor.minFilter)
            magFilter = Self.name(descriptor.magFilter)
            mipFilter = Self.name(descriptor.mipFilter)
            sAddressMode = Self.name(descriptor.sAddressMode)
            tAddressMode = Self.name(descriptor.tAddressMode)
            rAddressMode = Self.name(descriptor.rAddressMode)
            maxAnisotropy = descriptor.maxAnisotropy
        }

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
            ("mirrorRepeat", .mirrorRepeat), ("clampToZero", .clampToZero), ("clampToBorderColor", .clampToBorderColor),
        ]

        private static func name(_ mode: MTLSamplerAddressMode) -> String {
            addressModes.first { $0.1 == mode }?.0 ?? "clampToEdge"
        }

        private static func addressMode(_ name: String) -> MTLSamplerAddressMode {
            addressModes.first { $0.0 == name }?.1 ?? .clampToEdge
        }
    }

    // Reads `texture` back from the GPU and writes it once per archive. 2D 8-bit RGBA and BGRA textures are a PNG of
    // level 0 (mips are regenerated on load); everything else is raw bytes of every slice and mip level.
    // Names the texture's file. The bytes are written now, or by SceneArchive.Capture.write when capturing (#238).
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
                file: "\(SceneArchive.texturesDirectoryName)/\(index).bin", pixelFormat: texture.pixelFormat.rawValue, width: texture.width, height: texture.height, mipmapped: texture.mipmapLevelCount > 1,
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

    // The stored file's bytes: PNG data, or raw rows of `pixelFormat` texels.
    public func data(for reference: TextureReference) throws -> Data {
        try Data(contentsOf: readDirectory.appendingPathComponent(reference.file))
    }

    public func texture(for reference: TextureReference) throws -> MTLTexture {
        if let texture = readTextures[reference.file] {
            return texture
        }
        let device = try device
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
                 .astc_4x4_ldr, .astc_4x4_srgb, .astc_4x4_hdr:
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
        let device = try device
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
                    texture.replace(region: size.region, mipmapLevel: level, slice: slice, withBytes: buffer.baseAddress! + offset, bytesPerRow: size.bytesPerRow, bytesPerImage: size.bytesPerImage)
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
        let isStraightRGBA = image.bitsPerComponent == 8 && image.bitsPerPixel == 32 && image.alphaInfo == .last && image.bitmapInfo.intersection(.byteOrderMask).isEmpty
        if isStraightRGBA, let data = image.dataProvider?.data as Data? {
            var bytes = [UInt8](repeating: 0, count: width * height * 4)
            for row in 0 ..< height {
                let start = row * image.bytesPerRow
                bytes.replaceSubrange(row * width * 4 ..< (row + 1) * width * 4, with: data[start ..< start + width * 4])
            }
            return bytes
        }
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
