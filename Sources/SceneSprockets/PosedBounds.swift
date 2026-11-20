import GeometryLite3D
import simd

extension SceneGraph.MeshEntry {
    /// World bounds of the mesh as drawn: morphed and skinned, without deforming it. Conservative: it may be larger than
    /// the deformed mesh. Nil without mesh bounds.
    ///
    /// A morphed vertex moves by the sum of each target's delta times its weight, so the bounds grow by each target's
    /// smallest and largest delta times its weight. A skinned vertex is a weighted average of its joints' transforms, so
    /// it lies in the box around each joint's influenced vertices moved by that joint.
    public var posedWorldBounds: BoundingBox3D? {
        guard let meshBounds else {
            return nil
        }
        // Most entries are neither skinned nor morphed.
        if skin == nil, morphWeights.isEmpty {
            return meshBounds.transformed(by: worldTransform)
        }
        let morphGrowth = morphGrowth
        if let skin, let jointBounds = jointRestBounds() {
            let jointMatrices = skin.jointMatrices()
            var bounds: BoundingBox3D?
            for (joint, rest) in jointBounds.enumerated() {
                guard let rest, jointMatrices.indices.contains(joint) else {
                    continue
                }
                let grown = BoundingBox3D(min: rest.min + morphGrowth.min, max: rest.max + morphGrowth.max)
                let posed = grown.transformed(by: jointMatrices[joint])
                bounds = bounds.map { BoundingBox3D(min: simd_min($0.min, posed.min), max: simd_max($0.max, posed.max)) } ?? posed
            }
            // Skinned meshes are placed by their joints, not their node.
            return bounds ?? meshBounds.transformed(by: worldTransform)
        }
        return BoundingBox3D(min: meshBounds.min + morphGrowth.min, max: meshBounds.max + morphGrowth.max).transformed(by: worldTransform)
    }

    // Bounds of the morphed mesh in the node's space. Nil without mesh bounds.
    var posedLocalBounds: BoundingBox3D? {
        meshBounds.map { meshBounds in
            let morphGrowth = morphGrowth
            return BoundingBox3D(min: meshBounds.min + morphGrowth.min, max: meshBounds.max + morphGrowth.max)
        }
    }

    // Per axis, how far active morph targets can move a vertex down (min) and up (max).
    private var morphGrowth: (min: SIMD3<Float>, max: SIMD3<Float>) {
        var growth = (min: SIMD3<Float>.zero, max: SIMD3<Float>.zero)
        for (target, weight) in validMorphs where weight != 0 && !target.positionDeltas.isEmpty {
            let low = target.positionDeltas.reduce(SIMD3<Float>(repeating: .infinity)) { simd_min($0, $1) } * weight
            let high = target.positionDeltas.reduce(SIMD3<Float>(repeating: -.infinity)) { simd_max($0, $1) } * weight
            growth.min += simd_min(low, high)
            growth.max += simd_max(low, high)
        }
        return growth
    }

    // Rest-space bounds of the vertices each joint influences (nil for joints with none), cached on the node.
    // swiftlint:disable:next discouraged_optional_collection - nil means the mesh has no readable positions
    private func jointRestBounds() -> [BoundingBox3D?]? {
        let structure = node.revision.structure
        if let cached = renderCache.jointBounds, cached.structure == structure {
            return cached.bounds
        }
        let positions = HitTestGeometryCache.shared.positions(of: mesh.cpuReadable())
        guard !positions.isEmpty, positions.count == skinVertices.count, let skin else {
            return nil
        }
        var bounds = [BoundingBox3D?](repeating: nil, count: skin.jointIDs.count)
        for (position, influence) in zip(positions, skinVertices) {
            for slot in 0 ..< 4 where influence.weights[slot] != 0 {
                let joint = Int(influence.joints[slot])
                guard bounds.indices.contains(joint) else {
                    continue
                }
                bounds[joint] = bounds[joint].map { BoundingBox3D(min: simd_min($0.min, position), max: simd_max($0.max, position)) } ?? BoundingBox3D(min: position, max: position)
            }
        }
        renderCache.jointBounds = (structure, bounds)
        return bounds
    }
}
