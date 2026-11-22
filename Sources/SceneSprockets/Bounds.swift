import GeometryLite3D
import Metal
import MetalSupport
import simd
import SwiftMesh

extension MetalMesh {
    // Reads positions from the vertex buffers, through a shared copy for private storage (#303). Nil if there is no
    // float3 position attribute.
    func positionBounds() -> BoundingBox3D? {
        guard let attribute = vertexDescriptor.attributes.first(where: { $0.semantic == .position }),
              attribute.format == .float3,
              let buffer = vertexBuffers[attribute.bufferIndex],
              vertexCount > 0
        else {
            return nil
        }
        let stride = vertexDescriptor.layouts[attribute.bufferIndex]?.stride ?? 12
        let base = buffer.cpuReadable.contents().advanced(by: attribute.offset)
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
    /// Bounds of this node's mesh in its own space; nil for non-mesh nodes.
    public var meshBounds: BoundingBox3D? {
        if let cache = boundsCache.mesh, cache.revision == revision.structure {
            return cache.bounds
        }
        var bounds: BoundingBox3D?
        switch content {
        case let .mesh(mesh, _, _, _):
            bounds = mesh.positionBounds()
        case let .instancedMesh(mesh, _, transforms, _, _):
            // The union of every copy's bounds.
            if let local = mesh.positionBounds() {
                bounds = transforms.reduce(nil) { result, transform in
                    let copy = local.transformed(by: transform)
                    return result.map { $0.union(copy) } ?? copy
                }
            }
        default:
            break
        }
        boundsCache.mesh = (revision.structure, bounds)
        return bounds
    }

    /// Bounds of this node and its descendants in the parent's space (this node's transform applied). Nil if hidden.
    public var subtreeBounds: BoundingBox3D? {
        guard isShown else {
            return nil
        }
        if let cache = boundsCache.subtree, cache.revision == revision {
            return cache.bounds
        }
        // Fills the caches of stale descendants first, deepest last in `stale`, so each node below reads its children's
        // caches. An explicit stack, not recursion, so deep hierarchies do not overflow the stack (#603).
        var stale: [SceneGraph.Node] = []
        var stack: [SceneGraph.Node] = [self]
        while let node = stack.popLast() {
            stale.append(node)
            for child in node.children where child.isShown && child.boundsCache.subtree?.revision != child.revision {
                stack.append(child)
            }
        }
        for node in stale.reversed() {
            node.computeSubtreeBounds()
        }
        return boundsCache.subtree?.bounds
    }

    // Assumes every shown child's cache is current.
    private func computeSubtreeBounds() {
        var local = meshBounds
        for child in children where child.isShown {
            if let childBounds = child.boundsCache.subtree?.bounds {
                local = local.map { $0.union(childBounds) } ?? childBounds
            }
        }
        boundsCache.subtree = (revision, local?.transformed(by: composedTransform))
    }
}

extension SceneGraph {
    /// World-space bounds of every mesh in the graph.
    public var bounds: BoundingBox3D? {
        root.subtreeBounds
    }

    /// World-space bounds of `node` and its descendants. Nil if it or an ancestor is hidden.
    public func worldBounds(of node: Node) -> BoundingBox3D? {
        var ancestor = node.parent
        while let current = ancestor {
            guard current.isShown else {
                return nil
            }
            ancestor = current.parent
        }
        let parentTransform = node.parent?.worldTransform ?? .identity
        return node.subtreeBounds?.transformed(by: parentTransform)
    }
}
