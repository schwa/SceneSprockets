import Metal
import MetalSprocketsPBR
import MetalSprocketsPBRShaders
import SceneSprockets
import SceneSprocketsPBR
import simd
import SwiftMesh

// Materials for the keynote's PBR Extensions slide: speckled gummies (procedural noise texture, sheen, diffuse transmission,
// clearcoat) and pearls (thin-film iridescence).
@MainActor
enum PBRExtensionMaterials {
    // These only fail if Metal cannot allocate a tiny buffer.
    private static func make<T>(_ what: String, _ body: () throws -> T) -> T {
        do {
            return try body()
        } catch {
            fatalError("Cannot make the \(what): \(error)")
        }
    }

    private static func placeholder() -> PBRMaterial.Binding {
        make("placeholder texture binding") { try PBRMaterial.placeholderBinding(device: demoDevice) }
    }

    static func gummy(color: SIMD3<Float>, speckles: PBRMaterial.Binding) -> PBRSceneMaterial {
        var uniforms = PBRMaterialUniforms.defaults(baseColor: SIMD4(color, 1), metallic: 0, roughness: 0.4)
        uniforms.baseColor.enabled = 1
        uniforms.baseColor.transform = simd_float3x3(diagonal: [1.5, 1.5, 1])
        uniforms.sheenColorFactor = [1, 0.95, 0.9] * 0.25
        uniforms.sheenRoughnessFactor = 0.4
        uniforms.diffuseTransmissionFactor = 0.9
        uniforms.diffuseTransmissionColorFactor = color
        // Some blurred refraction of the surroundings makes the body read as jelly, not plastic.
        uniforms.transmissionFactor = 0.35
        uniforms.ior = 1.4
        // Thicker parts absorb more and go a deeper, more saturated color.
        uniforms.thicknessFactor = 1
        uniforms.attenuationDistance = 0.5
        uniforms.attenuationColor = simd_mix(color, color * color, [0.5, 0.5, 0.5])
        uniforms.volumeScatter = 1
        uniforms.multiscatterColorFactor = simd_mix(color, [1, 1, 1], [0.4, 0.4, 0.4])
        uniforms.clearcoatFactor = 0.25
        uniforms.clearcoatRoughnessFactor = 0.35
        var bindings = Array(repeating: placeholder(), count: Int(kPBRMaterialTextureCount.rawValue))
        bindings[Int(kPBRTextureBaseColor.rawValue)] = speckles
        return PBRSceneMaterial(make("gummy material") { try PBRMaterial(name: "Gummy", uniforms: uniforms, textureBindings: bindings, device: demoDevice) })
    }

    static func pearl() -> PBRSceneMaterial {
        var uniforms = PBRMaterialUniforms.defaults(baseColor: [0.85, 0.84, 0.92, 1], metallic: 0.35, roughness: 0.45)
        uniforms.iridescenceFactor = 1
        uniforms.iridescenceIor = 1.4
        uniforms.iridescenceThicknessMinimum = 400
        uniforms.iridescenceThicknessMaximum = 400
        uniforms.clearcoatFactor = 1
        uniforms.clearcoatRoughnessFactor = 0.1
        let placeholderBinding = placeholder()
        return PBRSceneMaterial(make("pearl material") { try PBRMaterial(name: "Pearl", uniforms: uniforms, placeholder: placeholderBinding, device: demoDevice) })
    }

    // MARK: Noise texture

    // White with soft value-noise mottling, sparse dark specks and fainter light flecks. Tinted by the base color factor.
    static func makeSpeckleBinding() -> PBRMaterial.Binding {
        let size = 1_024
        var random = SplitMix(seed: 0xC0FFEE)
        var pixels = [Float](repeating: 1, count: size * size)
        let lattice = (0..<(64 * 64)).map { _ in Float.random(in: 0...1, using: &random) }
        for y in 0..<size {
            for x in 0..<size {
                let low = valueNoise(Float(x) / Float(size) * 6, Float(y) / Float(size) * 6, lattice)
                let high = valueNoise(Float(x) / Float(size) * 32, Float(y) / Float(size) * 32, lattice)
                pixels[y * size + x] = 0.86 + 0.1 * low + 0.04 * high
            }
        }
        func stamp(count: Int, radius: ClosedRange<Float>, value: Float) {
            for _ in 0..<count {
                let cx = Float.random(in: 0..<Float(size), using: &random)
                let cy = Float.random(in: 0..<Float(size), using: &random)
                let r = Float.random(in: radius, using: &random)
                let extent = Int(r.rounded(.up)) + 1
                for dy in -extent...extent {
                    for dx in -extent...extent {
                        let px = (Int(cx) + dx + size) % size
                        let py = (Int(cy) + dy + size) % size
                        let distance = simd_length(SIMD2(Float(Int(cx) + dx) - cx, Float(Int(cy) + dy) - cy))
                        let coverage = simd_clamp(r - distance + 0.5, 0, 1)
                        pixels[py * size + px] = simd_mix(pixels[py * size + px], value, coverage)
                    }
                }
            }
        }
        stamp(count: 1_400, radius: 1...2, value: 1.15)
        stamp(count: 260, radius: 3...6, value: 0.05)

        var bytes = [UInt8](repeating: 255, count: size * size * 4)
        for index in 0..<(size * size) {
            let value = UInt8(simd_clamp(pixels[index], 0, 1) * 255)
            bytes[index * 4] = value
            bytes[index * 4 + 1] = value
            bytes[index * 4 + 2] = value
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm_srgb, width: size, height: size, mipmapped: true)
        descriptor.usage = .shaderRead
        let texture = demoDevice.makeTexture(descriptor: descriptor)!
        texture.label = "Speckles"
        texture.replace(region: MTLRegionMake2D(0, 0, size, size), mipmapLevel: 0, withBytes: bytes, bytesPerRow: size * 4)
        let queue = demoDevice.makeCommandQueue()!
        let commandBuffer = queue.makeCommandBuffer()!
        let blit = commandBuffer.makeBlitCommandEncoder()!
        blit.generateMipmaps(for: texture)
        blit.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        let samplerDescriptor = placeholder().samplerDescriptor
        return make("noise texture binding") { try PBRMaterial.Binding(texture: texture, samplerDescriptor: samplerDescriptor, device: demoDevice) }
    }

    // Tileable smooth value noise on a 64x64 lattice.
    private static func valueNoise(_ x: Float, _ y: Float, _ lattice: [Float]) -> Float {
        let period = 64
        let x0 = Int(floor(x)), y0 = Int(floor(y))
        let fx = x - Float(x0), fy = y - Float(y0)
        let sx = fx * fx * (3 - 2 * fx), sy = fy * fy * (3 - 2 * fy)
        func at(_ i: Int, _ j: Int) -> Float {
            lattice[((j % period + period) % period) * 64 + ((i % period + period) % period)]
        }
        let top = simd_mix(at(x0, y0), at(x0 + 1, y0), sx)
        let bottom = simd_mix(at(x0, y0 + 1), at(x0 + 1, y0 + 1), sx)
        return simd_mix(top, bottom, sy)
    }
}

private struct SplitMix: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

extension Mesh {
    // A box with rounded edges and corners: each face is a grid projected onto the rounded surface, with analytic normals.
    static func roundedBox(extents: SIMD3<Float>, radius: Float, segments: Int = 24) -> Mesh {
        let inner = extents / 2 - radius
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []
        var faces: [[Int]] = []
        // (normal, u axis, v axis) for each cube face, wound counter-clockwise when viewed from outside.
        let axes: [(SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)] = [
            ([0, 0, 1], [1, 0, 0], [0, 1, 0]), ([0, 0, -1], [-1, 0, 0], [0, 1, 0]),
            ([1, 0, 0], [0, 0, -1], [0, 1, 0]), ([-1, 0, 0], [0, 0, 1], [0, 1, 0]),
            ([0, 1, 0], [1, 0, 0], [0, 0, -1]), ([0, -1, 0], [1, 0, 0], [0, 0, 1])
        ]
        let outer = extents / 2
        for (faceIndex, (normal, uAxis, vAxis)) in axes.enumerated() {
            let base = positions.count
            for j in 0...segments {
                for i in 0...segments {
                    let u = Float(i) / Float(segments), v = Float(j) / Float(segments)
                    // Spread grid points toward the edges so the curved bands get enough rows.
                    let su = 0.5 - 0.5 * cos(u * .pi), sv = 0.5 - 0.5 * cos(v * .pi)
                    let onCube = (normal + uAxis * (su * 2 - 1) + vAxis * (sv * 2 - 1)) * outer
                    let core = simd_clamp(onCube, -inner, inner)
                    let direction = simd_normalize(onCube - core)
                    positions.append(core + direction * radius)
                    normals.append(direction)
                    uvs.append(SIMD2((u + Float(faceIndex % 3)) / 3, (v + Float(faceIndex / 3)) / 2))
                }
            }
            for j in 0..<segments {
                for i in 0..<segments {
                    let a = base + j * (segments + 1) + i
                    faces.append([a, a + 1, a + segments + 2, a + segments + 1])
                }
            }
        }
        var mesh = Mesh(positions: positions, faces: faces)
        var halfEdgeNormals = [SIMD3<Float>](repeating: .zero, count: mesh.topology.halfEdges.count)
        var halfEdgeUVs = [SIMD2<Float>](repeating: .zero, count: mesh.topology.halfEdges.count)
        for halfEdge in mesh.topology.halfEdges {
            halfEdgeNormals[halfEdge.id.raw] = normals[halfEdge.origin.raw]
            halfEdgeUVs[halfEdge.id.raw] = uvs[halfEdge.origin.raw]
        }
        mesh.normals = halfEdgeNormals
        mesh.textureCoordinates = halfEdgeUVs
        return mesh
    }
}
