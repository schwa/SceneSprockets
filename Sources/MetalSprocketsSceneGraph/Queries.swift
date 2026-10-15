import GeometryLite3D
import simd

// Projection and frustum queries, like SCNSceneRenderer's projectPoint, unprojectPoint, nodesInsideFrustum(of:) and
// isNode(_:insideFrustumOf:). `projectionMatrix` must map to Metal clip space (z in 0...w); view points have their
// origin top-left.
extension SceneGraph {
    // x and y in view coordinates; z is the clip-space depth (0...1, reversed for reversed-depth projections).
    public static func projectPoint(_ point: SIMD3<Float>, viewSize: SIMD2<Float>, cameraMatrix: simd_float4x4, projectionMatrix: simd_float4x4) -> SIMD3<Float> {
        let clip = projectionMatrix * cameraMatrix.inverse * SIMD4(point, 1)
        let ndc = SIMD3(clip.x, clip.y, clip.z) / clip.w
        return SIMD3((ndc.x + 1) / 2 * viewSize.x, (1 - ndc.y) / 2 * viewSize.y, ndc.z)
    }

    // The inverse of projectPoint: `point.z` is the clip-space depth.
    public static func unprojectPoint(_ point: SIMD3<Float>, viewSize: SIMD2<Float>, cameraMatrix: simd_float4x4, projectionMatrix: simd_float4x4) -> SIMD3<Float> {
        let ndc = SIMD4<Float>(point.x / viewSize.x * 2 - 1, 1 - point.y / viewSize.y * 2, point.z, 1)
        let world = cameraMatrix * projectionMatrix.inverse * ndc
        return SIMD3(world.x, world.y, world.z) / world.w
    }

    // Visible mesh nodes whose world bounds may be inside the frustum (a conservative test), in traversal order.
    public func nodesInsideFrustum(cameraMatrix: simd_float4x4, projectionMatrix: simd_float4x4) -> [Node] {
        let viewProjection = projectionMatrix * cameraMatrix.inverse
        var nodes: [Node] = []
        visit { node, worldTransform in
            if let bounds = node.meshBounds, isInFrustum(bounds.transformed(by: worldTransform), viewProjection: viewProjection) {
                nodes.append(node)
            }
        }
        return nodes
    }

    // Whether any part of `node`'s subtree may be inside the frustum. False if it or an ancestor is hidden.
    public func isNode(_ node: Node, insideFrustumWithCameraMatrix cameraMatrix: simd_float4x4, projectionMatrix: simd_float4x4) -> Bool {
        guard let bounds = worldBounds(of: node) else {
            return false
        }
        return isInFrustum(bounds, viewProjection: projectionMatrix * cameraMatrix.inverse)
    }
}
