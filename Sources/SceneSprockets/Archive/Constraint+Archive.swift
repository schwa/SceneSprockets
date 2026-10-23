import Foundation
import simd

// Constraints in scene.json (#161). Nodes they refer to are stored as child-index paths from the root, and resolved
// once the whole tree is read. Closure constraints (`.transform`) cannot be saved; they are skipped with a warning.
struct ArchivedConstraint: Codable {
    enum Kind: String, Codable {
        case lookAt, billboard, replicator, avoidOccluder, distance, inverseKinematics, acceleration
    }

    var kind: Kind
    var influenceFactor: Float = 1
    var isEnabled = true
    var target: [Int]?
    var chainRoot: [Int]?
    var worldUp: SIMD3<Float>?
    var localFront: SIMD3<Float>?
    var freeAxes: Int?
    var position: Bool?
    var orientation: Bool?
    var scale: Bool?
    var positionOffset: SIMD3<Float>?
    // x, y, z, w (real last).
    var orientationOffset: [Float]?
    var scaleOffset: SIMD3<Float>?
    var categoryBitMask: UInt?
    var bias: Float?
    var minimum: Float?
    var maximum: Float?
    var iterations: Int?
    var maximumAngle: Float?
    var maximumLinearAcceleration: Float?
    var maximumLinearVelocity: Float?
    var damping: Float?

    // Nil for constraints that cannot be saved, or whose nodes are not in the same graph.
    init?(_ constraint: SceneGraph.Constraint, root: SceneGraph.Node) {
        influenceFactor = constraint.influenceFactor
        isEnabled = constraint.isEnabled
        func path(_ node: SceneGraph.Node) -> [Int]? {
            node.archivePath(from: root)
        }
        switch constraint.kind {
        case let .lookAt(target, worldUp, localFront):
            guard let target = path(target) else {
                return nil
            }
            kind = .lookAt
            self.target = target
            self.worldUp = worldUp
            self.localFront = localFront
        case let .billboard(freeAxes):
            kind = .billboard
            self.freeAxes = freeAxes.rawValue
        case let .replicator(target, position, orientation, scale, positionOffset, orientationOffset, scaleOffset):
            guard let target = path(target) else {
                return nil
            }
            kind = .replicator
            self.target = target
            self.position = position
            self.orientation = orientation
            self.scale = scale
            self.positionOffset = positionOffset
            self.orientationOffset = [orientationOffset.imag.x, orientationOffset.imag.y, orientationOffset.imag.z, orientationOffset.real]
            self.scaleOffset = scaleOffset
        case let .avoidOccluder(target, categoryBitMask, bias):
            guard let target = path(target) else {
                return nil
            }
            kind = .avoidOccluder
            self.target = target
            self.categoryBitMask = categoryBitMask
            self.bias = bias
        case .transform:
            return nil
        case let .distance(target, minimum, maximum):
            guard let target = path(target) else {
                return nil
            }
            kind = .distance
            self.target = target
            self.minimum = minimum
            self.maximum = maximum
        case let .inverseKinematics(chainRoot, target, iterations, maximumAngle):
            guard let chainRoot = path(chainRoot), let target = path(target) else {
                return nil
            }
            kind = .inverseKinematics
            self.chainRoot = chainRoot
            self.target = target
            self.iterations = iterations
            self.maximumAngle = maximumAngle
        case let .acceleration(maximumLinearAcceleration, maximumLinearVelocity, damping):
            kind = .acceleration
            self.maximumLinearAcceleration = maximumLinearAcceleration
            self.maximumLinearVelocity = maximumLinearVelocity
            self.damping = damping
        }
    }

    // Nil when a referenced node is missing.
    func constraint(root: SceneGraph.Node) -> SceneGraph.Constraint? {
        func node(_ path: [Int]?) -> SceneGraph.Node? {
            path.flatMap { root.archiveNode(at: $0) }
        }
        let kind: SceneGraph.Constraint.Kind
        switch self.kind {
        case .lookAt:
            guard let target = node(target) else {
                return nil
            }
            kind = .lookAt(target: target, worldUp: worldUp ?? [0, 1, 0], localFront: localFront ?? [0, 0, -1])
        case .billboard:
            kind = .billboard(freeAxes: freeAxes.map(SceneGraph.BillboardAxes.init(rawValue:)) ?? .all)
        case .replicator:
            guard let target = node(target) else {
                return nil
            }
            let offset = orientationOffset ?? [0, 0, 0, 1]
            guard offset.count == 4 else {
                return nil
            }
            kind = .replicator(target: target, position: position ?? true, orientation: orientation ?? true, scale: scale ?? true, positionOffset: positionOffset ?? .zero, orientationOffset: simd_quatf(ix: offset[0], iy: offset[1], iz: offset[2], r: offset[3]), scaleOffset: scaleOffset ?? .one)
        case .avoidOccluder:
            guard let target = node(target) else {
                return nil
            }
            kind = .avoidOccluder(target: target, categoryBitMask: categoryBitMask ?? .max, bias: bias ?? 0.01)
        case .distance:
            guard let target = node(target) else {
                return nil
            }
            kind = .distance(target: target, minimum: minimum ?? 0, maximum: maximum ?? .infinity)
        case .inverseKinematics:
            guard let chainRoot = node(chainRoot), let target = node(target) else {
                return nil
            }
            kind = .inverseKinematics(chainRoot: chainRoot, target: target, iterations: iterations ?? 10, maximumAngle: maximumAngle ?? .pi)
        case .acceleration:
            kind = .acceleration(maximumLinearAcceleration: maximumLinearAcceleration ?? 3, maximumLinearVelocity: maximumLinearVelocity ?? 10, damping: damping ?? 0.1)
        }
        return SceneGraph.Constraint(kind, influenceFactor: influenceFactor, isEnabled: isEnabled)
    }
}

extension SceneGraph.Node {
    // Child indices from `root` down to this node; nil if it is not in `root`'s subtree.
    func archivePath(from root: SceneGraph.Node) -> [Int]? {
        var path: [Int] = []
        var node = self
        while node !== root {
            guard let parent = node.parent, let index = parent.children.firstIndex(where: { $0 === node }) else {
                return nil
            }
            path.append(index)
            node = parent
        }
        return path.reversed()
    }

    func archiveNode(at path: [Int]) -> SceneGraph.Node? {
        var node = self
        for index in path {
            guard node.children.indices.contains(index) else {
                return nil
            }
            node = node.children[index]
        }
        return node
    }
}
