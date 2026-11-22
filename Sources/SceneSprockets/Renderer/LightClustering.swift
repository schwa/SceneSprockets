import Metal
import MetalSprockets
import MetalSprocketsLighting
import MetalSprocketsLightingShaders
import MetalSupport
import simd

/// Whether ``SceneGraphElement`` assigns lights to clusters, so each fragment loops over the lights near it instead of
/// every light (#519). Blinn-Phong and PBR materials use the clusters; shader materials loop over every light.
public enum LightClustering: Sendable, Hashable {
    /// On when the frame has at least ``automaticMinimumLightCount`` direct lights.
    case automatic
    case on
    case off

    /// Below this many direct lights, looping over every light costs less than the assignment pass.
    public static let automaticMinimumLightCount = 16

    func isEnabled(lightCount: Int) -> Bool {
        switch self {
        case .automatic: lightCount >= Self.automaticMinimumLightCount
        case .on: lightCount > 0
        case .off: false
        }
    }
}

extension SceneGraphElement {
    /// Sets when lights are assigned to clusters. The default is ``LightClustering/automatic``.
    public func lightClustering(_ clustering: LightClustering) -> Self {
        var copy = self
        copy.lightClustering = clustering
        return copy
    }
}

extension RenderContext {
    /// The clusters for this frame's lights, or nil when clustering is off, the frame is stereo (one grid cannot
    /// serve several views) or there is nothing to cluster.
    func makeLightClusters(clustering: LightClustering, device: MTLDevice) throws -> LightingClusters? {
        let cameraPosition = cameraMatrix.columns.3.xyz
        let lights = lightingLights(cameraPosition: cameraPosition)
        guard stereoViews == nil, clustering.isEnabled(lightCount: lights.count) else {
            return nil
        }
        return try LightingClusters(lights: lights, cameraPosition: cameraPosition, projection: projectionMatrix, view: viewMatrix.rotationOnlyView, device: device)
    }
}

/// Fills ``LightingClusters/lightLists`` before the scene pass.
struct LightClusterPass: Element {
    var clusters: LightingClusters

    var body: some Element {
        get throws {
            let kernel = try LightClusterShaders.kernel()
            let size = clusters.uniforms.gridSize
            return try ComputePass(label: "Light Clusters") {
                try ComputePipeline(label: "Light Clusters", computeKernel: kernel) {
                    try ComputeDispatch(
                        threadsPerGrid: MTLSize(width: Int(size.x), height: Int(size.y), depth: Int(size.z)),
                        threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1)
                    )
                    .parameters { parameters in
                        parameters.set("uniforms", value: clusters.uniforms)
                        // Never empty: Metal needs a buffer even when lightCount is 0.
                        parameters.set("lights", values: clusters.lights.isEmpty ? [LightingLight()] : clusters.lights)
                        parameters.set("cornerRays", buffer: clusters.cornerRays)
                        parameters.set("clusterLights", buffer: clusters.lightLists)
                    }
                }
            }
            // Fragment shaders of the scene and pre-passes read the lists.
            .barrierAfterPass(after: .dispatch, beforeQueueStages: [.fragment, .dispatch])
        }
    }
}

enum LightClusterShaders {
    nonisolated(unsafe) private static var cached: ComputeKernel?
    private static let lock = NSLock()

    static func kernel() throws -> ComputeKernel {
        lock.lock()
        defer { lock.unlock() }
        if let cached {
            return cached
        }
        let kernel: ComputeKernel = try ShaderLibrary(bundle: .metalSprocketsLightingShaders()).namespaced("LightClusters").assign_lights
        cached = kernel
        return kernel
    }
}
