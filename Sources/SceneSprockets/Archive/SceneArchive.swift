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

    public init(materialTypes: [any ArchivableMaterial.Type] = [], environmentMapTypes: [any ArchivableEnvironmentMap.Type] = []) {
        self.materialTypes = materialTypes
        self.environmentMapTypes = environmentMapTypes
    }

    // Replaces anything at `url`. Returns warnings for what could not be saved.
    @discardableResult
    public func write(_ sceneGraph: SceneGraph, to url: URL) throws -> [String] {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        let context = SceneArchiveContext(directory: url, device: nil, archive: self)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        encoder.userInfo[.sceneArchive] = context
        try encoder.encode(sceneGraph).write(to: url.appendingPathComponent(Self.sceneFileName))
        return context.warnings
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
    let directory: URL
    let archive: SceneArchive
    private let readDevice: MTLDevice?
    public private(set) var warnings: [String] = []
    private var writtenTextures: [ObjectIdentifier: TextureReference] = [:]
    private var readTextures: [String: MTLTexture] = [:]

    init(directory: URL, device: MTLDevice?, archive: SceneArchive) {
        self.directory = directory
        self.readDevice = device
        self.archive = archive
    }

    public var device: MTLDevice {
        get throws {
            try readDevice.orThrow(SceneArchiveError.missingDevice)
        }
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
    }

    // Reads `texture` back from the GPU (level 0) and writes it once per archive: 8-bit RGBA and BGRA as PNG,
    // other formats as raw bytes.
    public func encode(texture: MTLTexture) throws -> TextureReference {
        if let reference = writtenTextures[ObjectIdentifier(texture)] {
            return reference
        }
        guard texture.textureType == .type2D else {
            throw SceneArchiveError.unsupportedTexture("type \(texture.textureType.rawValue)")
        }
        guard let bytesPerPixel = Self.bytesPerPixel(texture.pixelFormat) else {
            throw SceneArchiveError.unsupportedTexture("pixel format \(texture.pixelFormat.rawValue)")
        }
        var bytes = try Self.readBack(texture, bytesPerPixel: bytesPerPixel)
        let index = writtenTextures.count
        let isPNG = Self.pngFormats.contains(texture.pixelFormat)
        let file = "\(SceneArchive.texturesDirectoryName)/\(index).\(isPNG ? "png" : "bin")"
        let url = directory.appendingPathComponent(file)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if isPNG {
            if [.bgra8Unorm, .bgra8Unorm_srgb].contains(texture.pixelFormat) {
                for pixel in stride(from: 0, to: bytes.count, by: 4) {
                    bytes.swapAt(pixel, pixel + 2)
                }
            }
            try Self.writePNG(bytes: bytes, width: texture.width, height: texture.height, to: url)
        } else {
            try Data(bytes).write(to: url)
        }
        let reference = TextureReference(file: file, pixelFormat: texture.pixelFormat.rawValue, width: texture.width, height: texture.height, mipmapped: texture.mipmapLevelCount > 1)
        writtenTextures[ObjectIdentifier(texture)] = reference
        return reference
    }

    // The stored file's bytes: PNG data, or raw rows of `pixelFormat` texels.
    public func data(for reference: TextureReference) throws -> Data {
        try Data(contentsOf: directory.appendingPathComponent(reference.file))
    }

    public func texture(for reference: TextureReference) throws -> MTLTexture {
        if let texture = readTextures[reference.file] {
            return texture
        }
        let device = try device
        let url = directory.appendingPathComponent(reference.file)
        let pixelFormat = MTLPixelFormat(rawValue: reference.pixelFormat) ?? .rgba8Unorm
        guard let bytesPerPixel = Self.bytesPerPixel(pixelFormat) else {
            throw SceneArchiveError.unsupportedTexture("pixel format \(reference.pixelFormat)")
        }
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

    private static func bytesPerPixel(_ format: MTLPixelFormat) -> Int? {
        switch format {
        case .r8Unorm: 1
        case .rg8Unorm, .r16Float: 2
        case .rgba8Unorm, .rgba8Unorm_srgb, .bgra8Unorm, .bgra8Unorm_srgb, .r32Float, .rg16Float: 4
        case .rgba16Float, .rg32Float: 8
        case .rgba32Float: 16
        default: nil
        }
    }

    // Copies level 0 into a shared buffer when the texture is not CPU readable.
    private static func readBack(_ texture: MTLTexture, bytesPerPixel: Int) throws -> [UInt8] {
        let bytesPerRow = texture.width * bytesPerPixel
        var bytes = [UInt8](repeating: 0, count: bytesPerRow * texture.height)
        let region = MTLRegionMake2D(0, 0, texture.width, texture.height)
        if texture.storageMode == .shared {
            texture.getBytes(&bytes, bytesPerRow: bytesPerRow, from: region, mipmapLevel: 0)
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
        blit.copy(from: texture, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(), sourceSize: MTLSize(width: texture.width, height: texture.height, depth: 1), to: buffer, destinationOffset: 0, destinationBytesPerRow: bytesPerRow, destinationBytesPerImage: bytes.count)
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
    private static func writePNG(bytes: [UInt8], width: Int, height: Int, to url: URL) throws {
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else {
            throw SceneArchiveError.unsupportedTexture("could not encode PNG")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw SceneArchiveError.unsupportedTexture("could not write \(url.lastPathComponent)")
        }
    }
}
