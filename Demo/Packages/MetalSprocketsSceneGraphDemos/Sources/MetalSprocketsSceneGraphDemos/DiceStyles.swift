import CoreGraphics
import ImageIO
import Metal
import MetalKit
import MetalSprocketsPBR
import MetalSprocketsPBRShaders
import MetalSprocketsSceneGraphPBR
import simd

// PBR looks for the dice: each style is a body material and a number material, split by the die's numbers mask (white
// numbers on transparency). The mask drives base color, metallic/roughness, transmission and emission textures, so
// numbers can be enamel on gold, opaque inlays in glass, or glowing paint.
@MainActor
enum DiceStyle: String, CaseIterable {
    case classicRed = "Classic Red"
    case classicIvory = "Classic Ivory"
    case rubyGlass = "Ruby Glass"
    case crystal = "Rainbow Crystal"
    case gold = "Gold"
    case brushedSteel = "Brushed Steel"
    case pearl = "Pearl"
    case glow = "Glow"
    case velvet = "Velvet"
    case candy = "Candy Paint"
    case gummy = "Gummy"
    case marble = "Marble"

    // One side of the mask: color (linear RGB), roughness and metalness.
    struct Surface {
        var color: SIMD3<Float>
        var roughness: Float
        var metallic: Float = 0
    }

    var body: Surface {
        switch self {
        case .classicRed: Surface(color: [0.3, 0.005, 0.01], roughness: 0.35)
        case .classicIvory: Surface(color: [0.7, 0.62, 0.48], roughness: 0.4)
        case .rubyGlass: Surface(color: [1, 1, 1], roughness: 0.02)
        case .crystal: Surface(color: [1, 1, 1], roughness: 0)
        case .gold: Surface(color: [1, 0.77, 0.34], roughness: 0.18, metallic: 1)
        case .brushedSteel: Surface(color: [0.8, 0.8, 0.82], roughness: 0.3, metallic: 1)
        case .pearl: Surface(color: [0.92, 0.9, 0.95], roughness: 0.35, metallic: 0.2)
        case .glow: Surface(color: [0.008, 0.008, 0.012], roughness: 0.6)
        case .velvet: Surface(color: [0.1, 0.002, 0.02], roughness: 0.9)
        case .candy: Surface(color: [0.2, 0.01, 0.4], roughness: 0.35, metallic: 0.8)
        case .gummy: Surface(color: [0.15, 0.75, 0.2], roughness: 0.35)
        case .marble: Surface(color: [0.9, 0.9, 0.88], roughness: 0.25)
        }
    }

    var numbers: Surface {
        switch self {
        case .classicRed, .crystal: Surface(color: [1, 1, 1], roughness: 0.4)
        case .classicIvory, .pearl: Surface(color: [0.01, 0.01, 0.01], roughness: 0.5)
        case .rubyGlass, .velvet, .marble: Surface(color: [1, 0.77, 0.34], roughness: 0.2, metallic: 1)
        case .gold: Surface(color: [0.02, 0.02, 0.02], roughness: 0.6)
        case .brushedSteel: Surface(color: [0.6, 0.02, 0.02], roughness: 0.4)
        case .glow: Surface(color: [0.1, 0.9, 1], roughness: 0.5)
        case .candy, .gummy: Surface(color: [0.95, 0.95, 0.95], roughness: 0.3)
        }
    }

    // The material for one die kind in this style. `mask` is the kind's numbers texture, `normal` its bumps.
    func material(mask: CGImage, normal: MTLTexture) throws -> PBRSceneMaterial {
        let placeholder = try PBRMaterial.placeholderBinding(device: demoDevice)
        let sampler = placeholder.sampler
        var bindings = Array(repeating: placeholder, count: Int(kPBRMaterialTextureCount.rawValue))
        func bind(_ index: PBRMaterialTextureIndex, _ texture: MTLTexture) {
            bindings[Int(index.rawValue)] = .init(texture: texture, sampler: sampler)
        }
        var uniforms = PBRMaterialUniforms.defaults(baseColor: [1, 1, 1, 1], metallic: 1, roughness: 1)
        let body = body, numbers = numbers
        bind(kPBRTextureBaseColor, try Self.split(mask, sRGB: true, body: self == .marble ? .marble : .color(Self.sRGB(body.color)), numbers: Self.sRGB(numbers.color)))
        uniforms.baseColor.enabled = 1
        // Roughness in green, metalness in blue.
        bind(kPBRTextureMetallicRoughness, try Self.split(mask, sRGB: false, body: .color([0, body.roughness, body.metallic]), numbers: [0, numbers.roughness, numbers.metallic]))
        uniforms.metallicRoughness.enabled = 1
        bind(kPBRTextureNormal, normal)
        uniforms.normal.enabled = 1

        switch self {
        case .classicRed, .classicIvory:
            uniforms.clearcoatFactor = 0.15
            uniforms.clearcoatRoughnessFactor = 0.2
        case .rubyGlass, .crystal:
            // The body transmits; the numbers are opaque inlays.
            bind(kPBRTextureTransmission, try Self.split(mask, sRGB: false, body: .color([1, 1, 1]), numbers: [0, 0, 0]))
            uniforms.transmission.enabled = 1
            uniforms.transmissionFactor = 1
            uniforms.thicknessFactor = 0.4
            if self == .rubyGlass {
                uniforms.ior = 1.6
                uniforms.attenuationDistance = 0.15
                uniforms.attenuationColor = [0.85, 0.05, 0.1]
            } else {
                uniforms.ior = 1.8
                uniforms.dispersion = 1
            }
        case .gold:
            uniforms.clearcoatFactor = 0.2
            uniforms.clearcoatRoughnessFactor = 0.1
        case .brushedSteel:
            uniforms.anisotropyStrength = 0.85
            uniforms.anisotropyRotation = .pi / 4
        case .pearl:
            uniforms.iridescenceFactor = 1
            uniforms.iridescenceIor = 1.4
            uniforms.iridescenceThicknessMinimum = 250
            uniforms.iridescenceThicknessMaximum = 500
            uniforms.clearcoatFactor = 1
            uniforms.clearcoatRoughnessFactor = 0.08
        case .glow:
            // Glowing paint in the numbers only.
            bind(kPBRTextureEmissive, try Self.split(mask, sRGB: true, body: .color([0, 0, 0]), numbers: Self.sRGB(numbers.color)))
            uniforms.emissive.enabled = 1
            uniforms.emissiveFactor = [1, 1, 1]
            uniforms.emissiveStrength = 6
        case .velvet:
            uniforms.sheenColorFactor = [1, 0.35, 0.45]
            uniforms.sheenRoughnessFactor = 0.4
        case .candy:
            uniforms.clearcoatFactor = 1
            uniforms.clearcoatRoughnessFactor = 0.03
        case .gummy:
            uniforms.diffuseTransmissionFactor = 0.9
            uniforms.diffuseTransmissionColorFactor = body.color
            uniforms.transmissionFactor = 0.3
            uniforms.ior = 1.4
            uniforms.thicknessFactor = 1
            uniforms.attenuationDistance = 0.4
            uniforms.attenuationColor = body.color * body.color
            uniforms.volumeScatter = 1
            uniforms.multiscatterColorFactor = simd_mix(body.color, [1, 1, 1], [0.4, 0.4, 0.4])
            uniforms.sheenColorFactor = [0.25, 0.25, 0.25]
            uniforms.sheenRoughnessFactor = 0.4
            uniforms.clearcoatFactor = 0.3
            uniforms.clearcoatRoughnessFactor = 0.3
        case .marble:
            uniforms.clearcoatFactor = 1
            uniforms.clearcoatRoughnessFactor = 0.05
        }
        return PBRSceneMaterial(try PBRMaterial(name: rawValue, uniforms: uniforms, textureBindings: bindings, device: demoDevice))
    }

    // MARK: Textures

    private enum Fill {
        case color(SIMD3<Float>)
        case marble
    }

    // 0...1 channels from linear color, for an sRGB texture.
    private static func sRGB(_ linear: SIMD3<Float>) -> SIMD3<Float> {
        func encode(_ value: Float) -> Float {
            value <= 0.0031308 ? value * 12.92 : 1.055 * pow(value, 1 / 2.4) - 0.055
        }
        return [encode(linear.x), encode(linear.y), encode(linear.z)]
    }

    // A texture the size of `mask`: `body` where the mask is clear, `numbers` where it is opaque.
    private static func split(_ mask: CGImage, sRGB: Bool, body: Fill, numbers: SIMD3<Float>) throws -> MTLTexture {
        let width = mask.width, height = mask.height
        let space = sRGB ? CGColorSpace(name: CGColorSpace.sRGB)! : CGColorSpace(name: CGColorSpace.linearSRGB)!
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw CocoaError(.featureUnsupported)
        }
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        switch body {
        case .color(let color):
            context.setFillColor(red: CGFloat(color.x), green: CGFloat(color.y), blue: CGFloat(color.z), alpha: 1)
            context.fill(bounds)
        case .marble:
            context.draw(marblePattern(width: width, height: height), in: bounds)
        }
        // The mask's alpha picks the number pixels.
        context.saveGState()
        context.clip(to: bounds, mask: alphaMask(mask))
        context.setFillColor(red: CGFloat(numbers.x), green: CGFloat(numbers.y), blue: CGFloat(numbers.z), alpha: 1)
        context.fill(bounds)
        context.restoreGState()
        guard let image = context.makeImage() else {
            throw CocoaError(.featureUnsupported)
        }
        return try MTKTextureLoader(device: demoDevice).newTexture(cgImage: image, options: [.SRGB: sRGB, .generateMipmaps: true, .textureStorageMode: MTLStorageMode.private.rawValue, .origin: MTKTextureLoader.Origin.flippedVertically])
    }

    // The alpha of `image` as a grayscale mask image (white where opaque).
    private static func alphaMask(_ image: CGImage) -> CGImage {
        let width = image.width, height = image.height
        let rgba = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        rgba.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let pixels = rgba.data!.assumingMemoryBound(to: UInt8.self)
        let gray = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        let out = gray.data!.assumingMemoryBound(to: UInt8.self)
        for index in 0..<(width * height) {
            out[index] = pixels[index * 4 + 3]
        }
        return gray.makeImage()!
    }

    // White stone with soft grey veins: fractal value noise bent through a sine.
    private static func marblePattern(width: Int, height: Int) -> CGImage {
        var random = MarbleRandom(state: 0x5EED)
        let lattice = (0..<(64 * 64)).map { _ in Float(random.next() >> 40) / Float(1 << 24) }
        func noise(_ x: Float, _ y: Float) -> Float {
            let x0 = Int(floor(x)), y0 = Int(floor(y))
            let fx = x - Float(x0), fy = y - Float(y0)
            let sx = fx * fx * (3 - 2 * fx), sy = fy * fy * (3 - 2 * fy)
            func at(_ i: Int, _ j: Int) -> Float {
                lattice[((j % 64 + 64) % 64) * 64 + ((i % 64 + 64) % 64)]
            }
            return simd_mix(simd_mix(at(x0, y0), at(x0 + 1, y0), sx), simd_mix(at(x0, y0 + 1), at(x0 + 1, y0 + 1), sx), sy)
        }
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let pixels = context.data!.assumingMemoryBound(to: UInt8.self)
        for y in 0..<height {
            for x in 0..<width {
                let u = Float(x) / Float(width) * 8, v = Float(y) / Float(height) * 8
                var turbulence: Float = 0
                var amplitude: Float = 1, frequency: Float = 1
                for _ in 0..<5 {
                    turbulence += noise(u * frequency, v * frequency) * amplitude
                    amplitude *= 0.5
                    frequency *= 2
                }
                let vein = pow(abs(sin((u + v) * 1.3 + turbulence * 5)), 0.25)
                let value = 0.55 + 0.42 * vein
                let offset = (y * width + x) * 4
                pixels[offset] = UInt8(value * 245)
                pixels[offset + 1] = UInt8(value * 245)
                pixels[offset + 2] = UInt8(value * 240)
                pixels[offset + 3] = 255
            }
        }
        return context.makeImage()!
    }
}

private struct MarbleRandom {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
