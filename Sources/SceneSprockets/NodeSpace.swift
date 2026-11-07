import GeometryLite3D
import simd

// World-space accessors and space conversion, like SCNNode's worldTransform, worldPosition, worldOrientation,
// eulerAngles, convertPosition/convertVector/convertTransform and look(at:up:localFront:).
extension SceneGraph.Node {
    /// Includes `pivot`. Setting it keeps the local transform's kind: a TRS node stays TRS (decomposed, so lossy for
    /// skew), a matrix node stays a matrix.
    public var worldTransform: float4x4 {
        get {
            var result = composedTransform
            var node = parent
            while let current = node {
                result = current.composedTransform * result
                node = current.parent
            }
            return result
        }
        set {
            let parentWorld = parent?.worldTransform ?? .identity
            let local = parentWorld.inverse * newValue * pivot
            switch localTransform {
            case .trs:
                trs = Transform3D(decomposing: local)
            case .matrix:
                transform = local
            }
        }
    }

    /// The position of the node's origin in world space. Setting it moves the node.
    public var worldPosition: SIMD3<Float> {
        get { worldTransform.columns.3.xyz }
        set {
            var world = worldTransform
            world.columns.3 = SIMD4(newValue, 1)
            worldTransform = world
        }
    }

    /// The orientation of the node in world space. Setting it turns the node.
    public var worldOrientation: simd_quatf {
        get { Transform3D(decomposing: worldTransform).rotation }
        set {
            var world = Transform3D(decomposing: worldTransform)
            world.rotation = newValue
            worldTransform = world.matrix
        }
    }

    /// The local rotation as Euler angles (ZYX order: yaw about Z, pitch about Y, roll about X, in radians).
    public var eulerAngles: Euler {
        get { Euler(trs.rotation) }
        set { trs.rotation = simd_quatf(newValue) }
    }

    /// Converts from `node`'s space (nil for world space) to this node's space.
    public func convertPosition(_ position: SIMD3<Float>, from node: SceneGraph.Node?) -> SIMD3<Float> {
        (conversion(from: node) * SIMD4(position, 1)).xyz
    }

    /// Converts from this node's space to `node`'s space (nil for world space).
    public func convertPosition(_ position: SIMD3<Float>, to node: SceneGraph.Node?) -> SIMD3<Float> {
        (conversion(to: node) * SIMD4(position, 1)).xyz
    }

    /// Directions ignore translation; they are not normalized.
    public func convertVector(_ vector: SIMD3<Float>, from node: SceneGraph.Node?) -> SIMD3<Float> {
        (conversion(from: node) * SIMD4(vector, 0)).xyz
    }

    /// Converts a direction from this node's space to a node's space, or to world space if the node is `nil`.
    ///
    /// Directions ignore translation. The result is not normalized.
    public func convertVector(_ vector: SIMD3<Float>, to node: SceneGraph.Node?) -> SIMD3<Float> {
        (conversion(to: node) * SIMD4(vector, 0)).xyz
    }

    /// Converts a transform from a node's space, or from world space if the node is `nil`, to this node's space.
    public func convertTransform(_ transform: float4x4, from node: SceneGraph.Node?) -> float4x4 {
        conversion(from: node) * transform
    }

    /// Converts a transform from this node's space to a node's space, or to world space if the node is `nil`.
    public func convertTransform(_ transform: float4x4, to node: SceneGraph.Node?) -> float4x4 {
        conversion(to: node) * transform
    }

    /// Turns the node once so `localFront` points at `worldTarget`, keeping `worldUp` up. Does nothing if the node is
    /// at the target. See Constraint.lookAt for a target that keeps being tracked.
    public func look(at worldTarget: SIMD3<Float>, up worldUp: SIMD3<Float> = [0, 1, 0], localFront: SIMD3<Float> = [0, 0, -1]) {
        let position = worldPosition
        guard simd_length(worldTarget - position) > 1e-6 else {
            return
        }
        worldOrientation = .lookRotation(from: position, to: worldTarget, up: worldUp, localFront: localFront)
    }

    private func conversion(from node: SceneGraph.Node?) -> float4x4 {
        worldTransform.inverse * (node?.worldTransform ?? .identity)
    }

    private func conversion(to node: SceneGraph.Node?) -> float4x4 {
        (node?.worldTransform ?? .identity).inverse * worldTransform
    }
}
