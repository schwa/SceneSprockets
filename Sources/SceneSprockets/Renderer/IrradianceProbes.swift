import CoreGraphics
import Foundation
import GeometryLite3D
import Metal
import MetalSprockets
import MetalSprocketsLighting
import MetalSprocketsSupport
import MetalSupport
import simd

extension SceneGraph {
    /// A grid of irradiance probes in a node's unit box (#532); see ``SceneGraph/Node/probeVolume``. Probes sit at the
    /// centers of `resolution` cells. Objects inside take the probes' light, blended at their bounds' center, instead
    /// of the environment's diffuse light (PBR) or in addition to the ambient light (Blinn-Phong).
    public struct ProbeVolume: Sendable, Equatable, Codable {
        /// Probes along x, y and z.
        public var resolution: SIMD3<Int>
        /// One per probe, x fastest, then y, then z. Empty until captured.
        public var coefficients: [IrradianceSH]

        public init(resolution: SIMD3<Int> = [2, 2, 2], coefficients: [IrradianceSH] = []) {
            self.resolution = simd_max(resolution, SIMD3(repeating: 1))
            self.coefficients = coefficients
        }

        var probeCount: Int { resolution.x * resolution.y * resolution.z }

        // A probe's position in the node's unit box.
        func localPosition(_ cell: SIMD3<Int>) -> SIMD3<Float> {
            (SIMD3<Float>(cell) + 0.5) / SIMD3<Float>(resolution) - 0.5
        }

        /// The probes' light at `local`, a point in the node's unit box, blended trilinearly; nil outside the box or
        /// before capture.
        public func irradiance(atLocal local: SIMD3<Float>) -> IrradianceSH? {
            guard coefficients.count == probeCount, simd_reduce_max(simd_abs(local)) <= 0.5 else {
                return nil
            }
            let grid = simd_clamp((local + 0.5) * SIMD3<Float>(resolution) - 0.5, .zero, SIMD3<Float>(resolution &- 1))
            let floored = grid.rounded(.down)
            let base = SIMD3<Int>(floored)
            let fraction = grid - floored
            var result = IrradianceSH.zero
            for corner in 0..<8 {
                let offset = SIMD3<Int>(corner & 1, (corner >> 1) & 1, (corner >> 2) & 1)
                let cell = simd_min(base &+ offset, resolution &- 1)
                let along = SIMD3<Float>(offset)
                let weights = along * fraction + (1 - along) * (1 - fraction)
                let index = cell.x + resolution.x * (cell.y + resolution.y * cell.z)
                result += coefficients[index] * (weights.x * weights.y * weights.z)
            }
            return result
        }

        /// Renders the opaque scene and background from each probe of `node`'s volume (six 90-degree views) and stores
        /// the light it sees as spherical harmonics in `node.probeVolume` (#532). Shadows, transparent meshes, particles
        /// and decals are not captured. Call it on the thread that edits the scene, after the scene changes.
        @MainActor
        public static func capture(sceneGraph: SceneGraph, node: Node, renderers: [any MaterialRenderer], faceSize: Int = 32) throws {
            guard var volume = node.probeVolume else {
                return
            }
            let device = _MTLCreateSystemDefaultDevice()
            func target(_ format: MTLPixelFormat) throws -> MTLTexture {
                let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: faceSize, height: faceSize, mipmapped: false)
                descriptor.usage = [.renderTarget, .shaderRead]
                descriptor.storageMode = format == .depth32Float ? .private : .shared
                guard let texture = device.makeTexture(descriptor: descriptor) else {
                    throw MetalSupportError.resourceCreationFailure("Probe capture target")
                }
                return texture
            }
            let color = try target(.rgba16Float)
            let renderer = try OffscreenRenderer(size: CGSize(width: faceSize, height: faceSize), colorTexture: color, depthTexture: try target(.depth32Float), clearDepth: 0)
            let camera = Camera(projection: PerspectiveProjection(verticalAngleOfView: .degrees(90), depthMode: .reversed(zClip: 0.01 ... 1_000)))
            let worldTransform = node.worldTransform
            let faces: [(forward: SIMD3<Float>, up: SIMD3<Float>)] = [([1, 0, 0], [0, 1, 0]), ([-1, 0, 0], [0, 1, 0]), ([0, 1, 0], [0, 0, -1]), ([0, -1, 0], [0, 0, 1]), ([0, 0, 1], [0, 1, 0]), ([0, 0, -1], [0, 1, 0])]
            var coefficients: [IrradianceSH] = []
            for z in 0..<volume.resolution.z {
                for y in 0..<volume.resolution.y {
                    for x in 0..<volume.resolution.x {
                        let position = (worldTransform * SIMD4(volume.localPosition([x, y, z]), 1)).xyz
                        var radiance = [SIMD4<Float>](repeating: .zero, count: 4)
                        for face in faces {
                            let right = simd_normalize(simd_cross(face.forward, face.up))
                            let cameraMatrix = simd_float4x4(columns: (SIMD4(right, 0), SIMD4(face.up, 0), SIMD4(-face.forward, 0), SIMD4(position, 1)))
                            let element = SceneGraphElement(sceneGraph: sceneGraph, cameraMatrix: cameraMatrix, aspectRatio: 1, renderers: renderers, cameraOverride: camera).capturingIrradiance()
                            _ = try renderer.render(element)
                            accumulate(color, faceSize: faceSize, forward: face.forward, right: right, up: face.up, into: &radiance)
                        }
                        coefficients.append(irradiance(from: radiance))
                    }
                }
            }
            volume.coefficients = coefficients
            node.probeVolume = volume
        }

        // The real spherical harmonic basis constants: Y00, and Y1m without its direction factor.
        private static let basisL0: Float = 0.282095
        private static let basisL1: Float = 0.488603

        // Adds each texel's radiance times the L0 and L1 basis functions and its solid angle: entries are
        // (L00, L1-1, L10, L11), each holding RGB in xyz.
        private static func accumulate(_ texture: MTLTexture, faceSize: Int, forward: SIMD3<Float>, right: SIMD3<Float>, up: SIMD3<Float>, into radiance: inout [SIMD4<Float>]) {
            var pixels = [Float16](repeating: 0, count: faceSize * faceSize * 4)
            texture.getBytes(&pixels, bytesPerRow: faceSize * 8, from: MTLRegionMake2D(0, 0, faceSize, faceSize), mipmapLevel: 0)
            for row in 0..<faceSize {
                for column in 0..<faceSize {
                    let u = (Float(column) + 0.5) / Float(faceSize) * 2 - 1
                    let v = 1 - (Float(row) + 0.5) / Float(faceSize) * 2
                    let length = sqrt(1 + u * u + v * v)
                    let direction = (forward + right * u + up * v) / length
                    // The solid angle of a cube-face texel.
                    let solidAngle = 4 / (Float(faceSize * faceSize) * length * length * length)
                    let index = (row * faceSize + column) * 4
                    let color = SIMD4<Float>(Float(pixels[index]), Float(pixels[index + 1]), Float(pixels[index + 2]), 0) * solidAngle
                    radiance[0] += color * basisL0
                    radiance[1] += color * (basisL1 * direction.y)
                    radiance[2] += color * (basisL1 * direction.z)
                    radiance[3] += color * (basisL1 * direction.x)
                }
            }
        }

        // Radiance coefficients to irradiance over pi: the cosine lobe scales L0 by pi and L1 by 2 pi / 3 (Ramamoorthi
        // and Hanrahan 2001), then each is multiplied by its basis constant so evaluation is a dot product.
        private static func irradiance(from radiance: [SIMD4<Float>]) -> IrradianceSH {
            let constant = radiance[0] * basisL0
            let linear = (1...3).map { radiance[$0] * (2.0 / 3.0 * basisL1) }
            func row(_ channel: Int) -> SIMD4<Float> {
                SIMD4(constant[channel], linear[0][channel], linear[1][channel], linear[2][channel])
            }
            return IrradianceSH(red: row(0), green: row(1), blue: row(2))
        }
    }
}

public extension RenderContext {
    /// Whether the scene has captured probe volumes (#532), so renderers should look up ``irradiance(at:)``.
    var hasIrradianceProbes: Bool {
        !probeVolumes.isEmpty
    }

    /// Indirect light from the scene's probe volumes at a world position (#532), or nil outside every volume.
    func irradiance(at position: SIMD3<Float>) -> IrradianceSH? {
        for (worldTransform, volume) in probeVolumes {
            let local = (worldTransform.inverse * SIMD4(position, 1)).xyz
            if let sh = volume.irradiance(atLocal: local) {
                return sh
            }
        }
        return nil
    }

    /// The probe light for an entry: at the center of its world bounds.
    func irradiance(for entry: SceneGraph.MeshEntry) -> IrradianceSH? {
        guard !probeVolumes.isEmpty else {
            return nil
        }
        let center = entry.meshBounds.map { ($0.min + $0.max) / 2 } ?? .zero
        return irradiance(at: (entry.worldTransform * SIMD4(center, 1)).xyz)
    }
}

extension SceneGraphElement {
    // For probe capture: linear output, opaque meshes and background only, no probes (#532).
    func capturingIrradiance() -> Self {
        var copy = self
        copy.capturesIrradiance = true
        return copy
    }
}
