import GeometryLite3D
import Metal
import MetalSupport
import SwiftMesh
import simd

extension MetalMesh {
    // Reads positions from the vertex buffers (shared storage). Nil if there is no float3 position attribute.
    func positionBounds() -> BoundingBox3D? {
        guard let attribute = vertexDescriptor.attributes.first(where: { $0.semantic == .position }),
              attribute.format == .float3,
              let buffer = vertexBuffers[attribute.bufferIndex],
              vertexCount > 0
        else {
            return nil
        }
        let stride = vertexDescriptor.layouts[attribute.bufferIndex]?.stride ?? 12
        let base = buffer.contents().advanced(by: attribute.offset)
        var lower = SIMD3<Float>(repeating: .infinity)
        var upper = SIMD3<Float>(repeating: -.infinity)
        for index in 0..<vertexCount {
            let pointer = base.advanced(by: index * stride)
            let position = SIMD3<Float>(
                pointer.loadUnaligned(fromByteOffset: 0, as: Float.self),
                pointer.loadUnaligned(fromByteOffset: 4, as: Float.self),
                pointer.loadUnaligned(fromByteOffset: 8, as: Float.self)
            )
            lower = simd_min(lower, position)
            upper = simd_max(upper, position)
        }
        return BoundingBox3D(min: lower, max: upper)
    }
}

extension SceneGraph.Node {
    // Bounds of this node's mesh in its own space; nil for non-mesh nodes.
    public var meshBounds: BoundingBox3D? {
        if let cache = boundsCache.mesh, cache.revision == revision.structure {
            return cache.bounds
        }
        var bounds: BoundingBox3D?
        if case let .mesh(mesh, _, _, _) = content {
            bounds = mesh.positionBounds()
        }
        boundsCache.mesh = (revision.structure, bounds)
        return bounds
    }

    // Bounds of this node and its descendants in the parent's space (this node's transform applied). Nil if hidden.
    public var subtreeBounds: BoundingBox3D? {
        guard isVisible else {
            return nil
        }
        if let cache = boundsCache.subtree, cache.revision == revision {
            return cache.bounds
        }
        var local = meshBounds
        for child in children {
            if let childBounds = child.subtreeBounds {
                local = local.map { $0.union(childBounds) } ?? childBounds
            }
        }
        let bounds = local?.transformed(by: composedTransform)
        boundsCache.subtree = (revision, bounds)
        return bounds
    }

    public var worldTransform: float4x4 {
        var result = composedTransform
        var node = parent
        while let current = node {
            result = current.composedTransform * result
            node = current.parent
        }
        return result
    }
}

extension SceneGraph {
    // World-space bounds of every mesh in the graph.
    public var bounds: BoundingBox3D? {
        root.subtreeBounds
    }

    // World-space bounds of `node` and its descendants. Nil if it or an ancestor is hidden.
    public func worldBounds(of node: Node) -> BoundingBox3D? {
        var ancestor = node.parent
        while let current = ancestor {
            guard current.isVisible else {
                return nil
            }
            ancestor = current.parent
        }
        let parentTransform = node.parent?.worldTransform ?? .identity
        return node.subtreeBounds?.transformed(by: parentTransform)
    }
}
