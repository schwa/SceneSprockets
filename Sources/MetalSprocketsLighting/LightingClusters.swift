import Foundation
import Metal
@_exported import MetalSprocketsLightingShaders
import MetalSupport
import simd

/// One frame's clustered light assignment (#519): the view frustum cut into tiles and depth slices, and the buffer a
/// compute pass (`LightClusters::assign_lights`) fills with the lights reaching each cluster. Renderers bind
/// ``uniforms(shadingOrigin:)`` and ``lightLists`` so their shaders loop over a fragment's cluster
/// (`Lighting::lightList`) instead of every light.
///
/// The light indices are into ``lights``, the frame's direct lights, camera-relative. A renderer may only use the
/// clusters when it binds that same list in that order.
///
/// A class, so renderers that copy their lighting settings through deep element bodies carry one pointer, not ~200
/// bytes of uniforms (a larger PBRFrameBindings overflowed test thread stacks).
public final class LightingClusters: @unchecked Sendable {
    /// Tiles across, tiles down, depth slices.
    public static let defaultGridSize: SIMD3<UInt32> = [16, 9, 24]

    /// Uniforms for the compute pass: lights and positions camera-relative.
    public let uniforms: LightingClusterUniforms
    /// The lights the clusters index, camera-relative.
    public let lights: [LightingLight]
    /// The camera's world position; shading origins are measured from it.
    public let cameraPosition: SIMD3<Float>
    /// Per cluster: a count, then up to `kLightingClusterMaxLights` light indices (`UInt32`). A count above
    /// `kLightingClusterMaxLights` means the cluster overflowed and is shaded with every light.
    public let lightLists: MTLBuffer
    /// The tile corner rays the compute pass bounds clusters with.
    public let cornerRays: MTLBuffer

    public var clusterCount: Int { Int(uniforms.gridSize.x * uniforms.gridSize.y * uniforms.gridSize.z) }

    /// - Parameters:
    ///   - lights: the frame's direct lights, positions relative to `cameraPosition`.
    ///   - projection: the camera's projection.
    ///   - view: the camera's view rotation (a view matrix without translation, for camera-relative positions).
    public init(lights: [LightingLight], cameraPosition: SIMD3<Float>, projection: simd_float4x4, view: simd_float4x4, device: MTLDevice, gridSize: SIMD3<UInt32> = LightingClusters.defaultGridSize) throws {
        let rays = Self.cornerRays(projection: projection, gridSize: gridSize)
        var uniforms = LightingClusterUniforms()
        uniforms.viewProjection = projection * view
        uniforms.view = view
        uniforms.originOffset = .zero
        uniforms.gridSize = gridSize
        uniforms.sliceNear = max(rays.near, 0.05)
        // Slices cover where bounded lights reach; past that, the last slice runs on.
        let reach = lights.filter { $0.type != .directional && $0.range > 0 }.map { simd_length($0.position) + $0.range }.max() ?? uniforms.sliceNear * 1_000
        uniforms.sliceFar = max(reach, uniforms.sliceNear * 2)
        uniforms.enabled = 1
        uniforms.lightCount = Int32(lights.count)
        self.uniforms = uniforms
        self.lights = lights
        self.cameraPosition = cameraPosition
        let clusterCount = Int(gridSize.x * gridSize.y * gridSize.z)
        guard let lightLists = device.makeBuffer(length: clusterCount * Int(kLightingClusterStride) * MemoryLayout<UInt32>.stride, options: .storageModePrivate) else {
            throw MetalSupportError.resourceCreationFailure("Failed to create light cluster buffer")
        }
        lightLists.label = "Light Clusters"
        guard let cornerRays = rays.values.withUnsafeBytes({ bytes in bytes.baseAddress.flatMap { device.makeBuffer(bytes: $0, length: bytes.count, options: .storageModeShared) } }) else {
            throw MetalSupportError.resourceCreationFailure("Failed to create light cluster ray buffer")
        }
        cornerRays.label = "Light Cluster Rays"
        self.lightLists = lightLists
        self.cornerRays = cornerRays
    }

    /// The uniforms for a renderer whose shading space has its origin at `shadingOrigin` (world space).
    public func uniforms(shadingOrigin: SIMD3<Float>) -> LightingClusterUniforms {
        var uniforms = uniforms
        uniforms.originOffset = shadingOrigin - cameraPosition
        return uniforms
    }

    /// What a renderer binds as `lightClusterUniforms` and `lightClusters`: these clusters' for its shading origin, or
    /// disabled uniforms and a placeholder buffer when `clusters` is nil.
    public static func binding(_ clusters: LightingClusters?, shadingOrigin: SIMD3<Float>, device: MTLDevice) throws -> (uniforms: LightingClusterUniforms, buffer: MTLBuffer) {
        if let clusters {
            return (clusters.uniforms(shadingOrigin: shadingOrigin), clusters.lightLists)
        }
        return (disabledUniforms, try placeholderBuffer(device: device))
    }

    nonisolated(unsafe) private static var placeholders: [ObjectIdentifier: MTLBuffer] = [:]
    private static let placeholderLock = NSLock()

    static func placeholderBuffer(device: MTLDevice) throws -> MTLBuffer {
        placeholderLock.lock()
        defer { placeholderLock.unlock() }
        if let buffer = placeholders[ObjectIdentifier(device)] {
            return buffer
        }
        guard let buffer = device.makeBuffer(length: 16, options: .storageModeShared) else {
            throw MetalSupportError.resourceCreationFailure("Failed to create light cluster placeholder buffer")
        }
        buffer.label = "Light Clusters Placeholder"
        placeholders[ObjectIdentifier(device)] = buffer
        return buffer
    }

    /// Uniforms that turn clustering off, for shaders that take cluster inputs but have none this frame.
    public static var disabledUniforms: LightingClusterUniforms {
        var uniforms = LightingClusterUniforms()
        uniforms.gridSize = [1, 1, 1]
        uniforms.sliceNear = 1
        uniforms.sliceFar = 2
        return uniforms
    }

    /// Origin and direction (as float4 pairs) of the rays through each tile corner, in view space, with origin z 0 and
    /// direction z -1; and the projection's near distance.
    static func cornerRays(projection: simd_float4x4, gridSize: SIMD3<UInt32>) -> (values: [SIMD4<Float>], near: Float) {
        let inverse = projection.inverse
        func unproject(_ x: Float, _ y: Float, _ z: Float) -> SIMD3<Float>? {
            let point = inverse * SIMD4(x, y, z, 1)
            guard abs(point.w) > 1e-12 else {
                return nil
            }
            let result = SIMD3(point.x, point.y, point.z) / point.w
            return result.x.isFinite && result.y.isFinite && result.z.isFinite ? result : nil
        }
        // Two depths that unproject to finite points: reverse-Z and infinite far planes leave one end at infinity.
        let depths = [Float(1), 0.5, 0.25, 0].filter { unproject(0, 0, $0) != nil }
        let first = depths.first ?? 1
        let second = depths.dropFirst().first ?? 0
        var near = Float.infinity
        var values: [SIMD4<Float>] = []
        for y in 0 ... gridSize.y {
            for x in 0 ... gridSize.x {
                let ndcX = -1 + 2 * Float(x) / Float(gridSize.x)
                let ndcY = -1 + 2 * Float(y) / Float(gridSize.y)
                guard let a = unproject(ndcX, ndcY, first), let b = unproject(ndcX, ndcY, second), abs(b.z - a.z) > 1e-12 else {
                    values += [.zero, [0, 0, -1, 0]]
                    continue
                }
                near = min(near, -a.z, -b.z)
                let direction = (b - a) / (a.z - b.z)
                let origin = a + direction * a.z
                values += [SIMD4(origin, 0), SIMD4(direction, 0)]
            }
        }
        return (values, near.isFinite ? near : 0)
    }
}
