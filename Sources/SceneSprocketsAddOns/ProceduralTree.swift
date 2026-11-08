import Metal
import SceneSprockets
import SceneSprocketsBlinnPhong
import simd

/// A tree grown from a seed: branches that split recursively, with leaf clusters near the tips.
///
/// The same parameters and seed always grow the same tree. Use ``makeNode(device:)`` for a ready-to-render node, or
/// read ``branches`` and ``leaves`` to build your own geometry.
public struct ProceduralTree {
    /// The shape and colors of a tree.
    public struct Parameters: Sendable, Equatable {
        /// The length of the trunk.
        public var trunkLength: Float = 3.4
        /// The radius at the base of the trunk.
        public var trunkRadius: Float = 0.42
        /// How many times branches split.
        public var depth: Int = 5
        /// The child branches at each split. Sometimes one more grows.
        public var branchCount: Int = 2
        /// How far, in radians, side branches turn away from their parent.
        public var spread: Float = 0.6
        /// Each child branch's length as a fraction of its parent's.
        public var lengthDecay: Float = 0.74
        /// How much branches wander. 0 is straight.
        public var gnarl: Float = 0.18
        /// How much the outer branches bend up (positive) or droop (negative).
        public var gravity: Float = 0.12
        /// The radius of a leaf cluster.
        public var leafSize: Float = 0.32
        /// The leaf clusters at each branch tip.
        public var leavesPerTip: Int = 4
        /// The color of the bark, in linear RGB.
        public var barkColor: SIMD3<Float> = [0.1, 0.06, 0.035]
        /// The colors that leaf clusters are picked from, in linear RGB. Empty for a bare tree.
        public var leafColors: [SIMD3<Float>] = [[0.05, 0.27, 0.04], [0.08, 0.38, 0.07], [0.03, 0.2, 0.03]]
        /// The most branch segments the tree grows. Growth stops when it is reached.
        public var maximumBranchCount: Int = 9_000

        /// Creates parameters. Change the properties to shape the tree.
        public init() {
            // Defaults are set on the properties.
        }

        /// Parameters picked at random from `seed`, within ranges that make plausible trees.
        public static func random(seed: UInt32) -> Self {
            var random = SeededRandom("parameters\(seed)")
            var parameters = Self()
            let weeping = random.next() < 0.2
            parameters.trunkLength = random.range(2.6, 4.2)
            parameters.trunkRadius = random.range(0.32, 0.55)
            parameters.depth = random.next() < 0.5 ? 5 : 6
            parameters.branchCount = random.next() < 0.55 ? 2 : 3
            parameters.spread = random.range(0.38, 0.85)
            parameters.lengthDecay = random.range(0.68, 0.8)
            parameters.gnarl = random.range(0.06, 0.32)
            parameters.gravity = weeping ? random.range(-0.6, -0.3) : random.range(-0.1, 0.35)
            parameters.leafSize = random.range(0.24, 0.4)
            parameters.leavesPerTip = Int(random.range(3, 6))
            parameters.barkColor *= random.range(0.6, 1.2)
            return parameters
        }
    }

    /// A branch segment: a tapered cylinder from `start` to `end`.
    public struct Branch: Sendable, Equatable {
        public var start: SIMD3<Float>
        public var end: SIMD3<Float>
        public var startRadius: Float
        public var endRadius: Float
    }

    /// A leaf cluster.
    public struct Leaf: Sendable, Equatable {
        public var position: SIMD3<Float>
        public var size: Float
        /// An angle in radians that turns the cluster, so clusters do not all face the same way.
        public var rotation: Float
        /// The index in ``Parameters/leafColors``.
        public var colorIndex: Int
    }

    /// The parameters the tree grew from.
    public let parameters: Parameters
    /// The seed the tree grew from.
    public let seed: UInt32
    /// The branch segments, trunk first. The trunk starts at the origin and grows up +Y.
    public private(set) var branches: [Branch] = []
    /// The leaf clusters.
    public private(set) var leaves: [Leaf] = []

    /// Grows a tree.
    ///
    /// - Parameters:
    ///   - parameters: The shape and colors.
    ///   - seed: The seed. The same parameters and seed always grow the same tree.
    public init(parameters: Parameters = .init(), seed: UInt32 = 0) {
        self.parameters = parameters
        self.seed = seed
        grow(path: "0", start: .zero, direction: [0, 1, 0], length: parameters.trunkLength, radius: parameters.trunkRadius, depth: 0)
    }

    // Each branch seeds its own generator from its path, so changing one part of the tree leaves the rest alone.
    private mutating func grow(path: String, start: SIMD3<Float>, direction initialDirection: SIMD3<Float>, length: Float, radius: Float, depth: Int) {
        guard branches.count < parameters.maximumBranchCount else {
            return
        }
        var random = SeededRandom("\(seed):\(path)")
        var direction = initialDirection
        var point = start
        let segments = 3
        for index in 0..<segments {
            direction.x += random.signed() * parameters.gnarl
            direction.z += random.signed() * parameters.gnarl
            direction.y += random.signed() * parameters.gnarl * 0.5
            direction.y += parameters.gravity * 0.12 * Float(depth) / Float(max(parameters.depth, 1))
            direction = simd_normalize(direction)
            let next = point + direction * length / Float(segments)
            let startRadius = radius * (1 - 0.28 * Float(index) / Float(segments))
            let endRadius = radius * (1 - 0.28 * Float(index + 1) / Float(segments))
            branches.append(Branch(start: point, end: next, startRadius: startRadius, endRadius: endRadius))
            point = next
        }

        if depth >= parameters.depth - 1, !parameters.leafColors.isEmpty {
            let base = depth == parameters.depth ? Float(parameters.leavesPerTip) : Float(parameters.leavesPerTip) * 0.4
            let count = max(1, Int((base + random.signed()).rounded()))
            for _ in 0..<count {
                let offset = SIMD3<Float>(random.signed(), random.signed() * 0.8, random.signed()) * parameters.leafSize * 2.4
                let colorIndex = min(Int(random.next() * Float(parameters.leafColors.count)), parameters.leafColors.count - 1)
                leaves.append(Leaf(position: point + offset, size: parameters.leafSize * random.range(0.6, 1.15), rotation: random.next() * 2 * .pi, colorIndex: colorIndex))
            }
        }
        guard depth < parameters.depth else {
            return
        }
        let childCount = parameters.branchCount + (random.next() < 0.3 ? 1 : 0)
        let reference: SIMD3<Float> = abs(direction.y) < 0.9 ? [0, 1, 0] : [1, 0, 0]
        let perpendicular = simd_normalize(simd_cross(direction, reference))
        let roll = random.next() * 2 * .pi
        for child in 0..<childCount {
            // The first child continues the parent; the others turn away by about `spread`, spaced by the golden angle.
            let continues = child == 0
            let angle = continues ? parameters.spread * 0.25 * random.next() : parameters.spread * random.range(0.75, 1.3)
            let side = simd_quatf(angle: roll + Float(child) * 2.39996, axis: direction).act(perpendicular)
            let childDirection = simd_normalize(direction * cos(angle) + side * sin(angle))
            let childLength = length * parameters.lengthDecay * (continues ? 1 : random.range(0.8, 1))
            let childRadius = radius * 0.72 * (continues ? 0.95 : random.range(0.7, 0.85))
            grow(path: "\(path).\(child)", start: point, direction: childDirection, length: childLength, radius: childRadius, depth: depth + 1)
        }
    }

    /// A node with the tree as one flat-shaded mesh: a bark submesh and a submesh per leaf color, with Blinn-Phong
    /// materials.
    ///
    /// - Parameter device: The device for the mesh.
    /// - Returns: The tree node, labeled "Tree".
    public func makeNode(device: MTLDevice) -> SceneGraph.Node {
        let builder = FlatMeshBuilder()
        builder.material("bark") { Self.matte(parameters.barkColor) }
        for branch in branches {
            builder.frustum("bark", from: branch.start, to: branch.end, startRadius: branch.startRadius, endRadius: branch.endRadius * 0.98)
            // Rounds the joint to the next segment.
            builder.icosahedron("bark", center: branch.end, scale: SIMD3(repeating: branch.endRadius * 0.95))
        }
        for leaf in leaves {
            let key = "leaves \(leaf.colorIndex)"
            builder.material(key) { Self.matte(parameters.leafColors[leaf.colorIndex], shininess: 12, specular: 0.08) }
            let rotation = simd_quatf(angle: leaf.rotation, axis: [0, 1, 0]) * simd_quatf(angle: leaf.rotation * 1.7, axis: [1, 0, 0])
            builder.icosahedron(key, center: leaf.position, scale: [leaf.size, leaf.size * 0.8, leaf.size], rotation: rotation)
        }
        let node = SceneGraph.Node(label: "Tree")
        if let (mesh, materials) = builder.build(device: device, label: "Tree") {
            node.content = .mesh(mesh, materials: materials)
        }
        return node
    }

    private static func matte(_ color: SIMD3<Float>, shininess: Float = 8, specular: Float = 0.05) -> BlinnPhongSceneMaterial {
        BlinnPhongSceneMaterial(ambient: .color(color), diffuse: .color(color), specular: .color(specular), shininess: shininess)
    }
}

// A small seeded generator (mulberry32), so a seed always grows the same tree on every platform.
struct SeededRandom {
    private var state: UInt32

    init(_ string: String) {
        // FNV-1a.
        var hash: UInt32 = 2_166_136_261
        for byte in string.utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 16_777_619
        }
        state = hash
    }

    mutating func next() -> Float {
        state = state &+ 0x6D2B_79F5
        var t = (state ^ (state >> 15)) &* (1 | state)
        t = (t &+ ((t ^ (t >> 7)) &* (61 | t))) ^ t
        return Float(Double(t ^ (t >> 14)) / 4_294_967_296)
    }

    mutating func range(_ lower: Float, _ upper: Float) -> Float {
        lower + (upper - lower) * next()
    }

    mutating func signed() -> Float {
        next() - 0.5
    }
}
