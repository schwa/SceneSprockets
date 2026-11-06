import Foundation
import simd

struct Season: Sendable {
    var name: String
    var leaves: [SIMD3<Float>]
    var skyTop: SIMD3<Float>
    var skyHorizon: SIMD3<Float>
    var ground: SIMD3<Float>
    var density: Float
    var tint: SIMD3<Float>
    var tintWord: String
    var sun: SIMD3<Float>
    var ambient: SIMD3<Float>
    var hasFlowers: Bool
    var palettes: [Palette] = []
    var treeKind = ""

    // A copy of the season with one of its tree palettes, chosen by the seed.
    func dressed(seed: UInt32) -> Season {
        var random = SeededRandom("palette\(seed)")
        let palette = random.pick(palettes)
        var season = self
        season.leaves = palette.leaves.map(linearColor)
        season.tint = linearColor(palette.tint)
        season.tintWord = palette.tintWord
        season.treeKind = palette.name
        return season
    }

    static let all: [Season] = [
        Season(name: "Spring", leaves: [0x86C96E, 0xA5D97F, 0x6BB85D, 0xB8E08A].map(linearColor), skyTop: linearColor(0x7FB8F0), skyHorizon: linearColor(0xFDE4E6), ground: linearColor(0x8FBF6A), density: 0.85, tint: linearColor(0xFF8FBE), tintWord: "pink", sun: linearColor(0xFFF1DC), ambient: [0.42, 0.45, 0.5], hasFlowers: true, palettes: [
            Palette(name: "Cherry blossom", leaves: [0xF7B7CF, 0xF29BBB, 0xFFD6E4, 0xFBE9EF], tint: 0x7CC46A, tintWord: "green"),
            Palette(name: "Magnolia", leaves: [0xFFF4F7, 0xF3D3E2, 0xE8B4CC], tint: 0xB0417A, tintWord: "plum"),
            Palette(name: "New leaves", leaves: [0x86C96E, 0xA5D97F, 0x6BB85D, 0xB8E08A], tint: 0xFF8FBE, tintWord: "pink"),
            Palette(name: "Crab apple", leaves: [0xE45C8A, 0xF07FA5, 0xD9467A, 0x8FC46A], tint: 0xFFFFFF, tintWord: "white")
        ]),
        Season(name: "Summer", leaves: [0x3F8F3A, 0x4FA547, 0x2E7D32, 0x5CAE3C].map(linearColor), skyTop: linearColor(0x3D86D6), skyHorizon: linearColor(0xFFEAC0), ground: linearColor(0x6EA04A), density: 1, tint: linearColor(0xE0A52C), tintWord: "gold", sun: linearColor(0xFFF3D6), ambient: [0.4, 0.43, 0.48], hasFlowers: true, palettes: [
            Palette(name: "Oak", leaves: [0x3F8F3A, 0x4FA547, 0x2E7D32, 0x5CAE3C], tint: 0xE0A52C, tintWord: "gold"),
            Palette(name: "Copper beech", leaves: [0x6B2E3A, 0x80394A, 0x5A2430, 0x8C4A4F], tint: 0x6FB04F, tintWord: "green"),
            Palette(name: "Jacaranda", leaves: [0x8E7CE0, 0xA593EB, 0x7766CC, 0xB7A9F2], tint: 0xF2D14B, tintWord: "yellow"),
            Palette(name: "Silver birch", leaves: [0x9CCB6A, 0xB6D98A, 0x84B85A], tint: 0xD9603B, tintWord: "rust")
        ]),
        Season(name: "Autumn", leaves: [0xD9822B, 0xC4452C, 0xE8B33A, 0xB8612A].map(linearColor), skyTop: linearColor(0x56679E), skyHorizon: linearColor(0xF8C58E), ground: linearColor(0x9A7B4F), density: 0.9, tint: linearColor(0x5F9E4F), tintWord: "green", sun: linearColor(0xFFD2A0), ambient: [0.45, 0.4, 0.38], hasFlowers: false, palettes: [
            Palette(name: "Maple", leaves: [0xC4302B, 0xD9452C, 0xE8642E, 0xA8241F], tint: 0xE8C23A, tintWord: "gold"),
            Palette(name: "Ginkgo", leaves: [0xF2C230, 0xE8B33A, 0xF7D85A, 0xD9A21F], tint: 0x5F9E4F, tintWord: "green"),
            Palette(name: "Mixed autumn", leaves: [0xD9822B, 0xC4452C, 0xE8B33A, 0xB8612A], tint: 0x8A3FA0, tintWord: "violet"),
            Palette(name: "Smoke bush", leaves: [0xB0413E, 0x8E2F4A, 0xD86A3A, 0x6E2A3F], tint: 0xF2C230, tintWord: "yellow")
        ]),
        Season(name: "Winter", leaves: [0xEEF4F7, 0xDBE6EC, 0xF7FBFC].map(linearColor), skyTop: linearColor(0x8AA2BB), skyHorizon: linearColor(0xEEF1F4), ground: linearColor(0xEEF3F6), density: 0.45, tint: linearColor(0xC43B4A), tintWord: "red", sun: linearColor(0xFFF6EE), ambient: [0.5, 0.52, 0.56], hasFlowers: false, palettes: [
            Palette(name: "Snowy", leaves: [0xEEF4F7, 0xDBE6EC, 0xF7FBFC], tint: 0xC43B4A, tintWord: "red"),
            Palette(name: "Evergreen", leaves: [0x2F5D4A, 0x3B6E58, 0xE8F0F2], tint: 0xC43B4A, tintWord: "red"),
            Palette(name: "Winter cherry", leaves: [0xF4C6D6, 0xEEF4F7, 0xE9AFC4], tint: 0x3B6E58, tintWord: "evergreen")
        ])
    ]
}

struct Palette: Sendable {
    var name: String
    var leaves: [UInt32]
    var tint: UInt32
    var tintWord: String
}

struct Species {
    var trunkLength: Float
    var trunkRadius: Float
    var depth: Int
    var kids: Int
    var spread: Float
    var decay: Float
    var gnarl: Float
    var gravity: Float
    var leafSize: Float
    var leafCount: Int
    var bark: SIMD3<Float>

    init(seed: UInt32) {
        var random = SeededRandom("species\(seed)")
        let weeping = random.next() < 0.2
        trunkLength = random.range(2.6, 4.2)
        trunkRadius = random.range(0.32, 0.55)
        depth = random.next() < 0.5 ? 5 : 6
        kids = random.next() < 0.55 ? 2 : 3
        spread = random.range(0.38, 0.85)
        decay = random.range(0.68, 0.8)
        gnarl = random.range(0.06, 0.32)
        gravity = weeping ? random.range(-0.6, -0.3) : random.range(-0.1, 0.35)
        leafSize = random.range(0.24, 0.4)
        leafCount = Int(random.range(3, 6))
        let barkShade = random.range(0.6, 1.2)
        bark = linearColor(0x5A4632) * barkShade
    }
}

enum Side: Sendable {
    case left, right
}

enum DifferenceKind: CaseIterable, Sendable {
    case prune, bend, tint, fruit, bird, blossom

    var captions: [String] {
        switch self {
        case .prune: ["One tree let a branch go. The other kept it.", "A limb that grew on only one of them.", "Absence, too, is a shape."]
        case .bend: ["A branch leaned toward a different light.", "The same branch, a different idea of up.", "One of them changed its mind halfway."]
        case .tint: ["Some leaves dreamed in another colour.", "A patch of {w}, quietly.", "A small rebellion of {w}."]
        case .fruit: ["One tree decided to bear fruit.", "Something ripe, on one side only."]
        case .bird: ["A visitor chose only one of them.", "A small bird with opinions.", "Someone sat down to rest here."]
        case .blossom: ["A quiet blossoming.", "Flowers, for no one in particular."]
        }
    }
}

struct Difference: Identifiable {
    let id = UUID()
    var kind: DifferenceKind
    var side: Side
    var path: String
    var anchor: SIMD3<Float>
    var axis: SIMD3<Float> = [1, 0, 0]
    var angle: Float = 0
    var yaw: Float = 0
    var birdColor: SIMD3<Float> = .zero
    var found = false
}

struct Branch {
    var a: SIMD3<Float>
    var b: SIMD3<Float>
    var radiusA: Float
    var radiusB: Float
}

struct Leaf {
    var position: SIMD3<Float>
    var size: Float
    var rotation: Float
    // Index into the season palette, or -1 for the tint colour.
    var paletteIndex: Int
    var shade: Int
}

struct Ornament {
    var position: SIMD3<Float>
    var size: Float
    var rotation: Float
}

struct Bird {
    var position: SIMD3<Float>
    var yaw: Float
    var color: SIMD3<Float>
}

struct NodeInfo {
    var depth: Int
    var start: SIMD3<Float>
    var end: SIMD3<Float>
}

struct GrownTree {
    var branches: [Branch] = []
    var leaves: [Leaf] = []
    var fruits: [Ornament] = []
    var blossoms: [Ornament] = []
    var birds: [Bird] = []
    var nodes: [String: NodeInfo] = [:]
}

private let up: SIMD3<Float> = [0, 1, 0]

func decorationPosition(end: SIMD3<Float>, species: Species) -> SIMD3<Float> {
    var outward = SIMD3<Float>(end.x, 0, end.z)
    if simd_length_squared(outward) < 1e-4 {
        outward = [1, 0, 0]
    }
    return end + simd_normalize(outward) * species.leafSize * 2.2 + [0, species.leafSize, 0]
}

// Grows a tree. Each node seeds its own generator from its path, so a mutation only changes its own subtree.
func growTree(species: Species, seed: UInt32, season: Season, differences: [String: Difference], side: Side?) -> GrownTree {
    var tree = GrownTree()
    let paletteCount = season.leaves.count

    func node(path: String, start: SIMD3<Float>, direction initialDirection: SIMD3<Float>, length: Float, radius: Float, depth: Int, tinted: Bool) {
        var random = SeededRandom("\(seed):\(path)")
        let difference = differences[path]
        let active = difference != nil && difference?.side == side
        var tinted = tinted
        var direction = initialDirection
        if active, let difference {
            switch difference.kind {
            case .prune: return
            case .bend: direction = simd_normalize(simd_quatf(angle: difference.angle, axis: difference.axis).act(direction))
            case .tint: tinted = true
            default: break
            }
        }
        var point = start
        let segments = 3
        for index in 0..<segments {
            direction.x += random.signed() * species.gnarl
            direction.z += random.signed() * species.gnarl
            direction.y += random.signed() * species.gnarl * 0.5
            direction.y += species.gravity * 0.12 * Float(depth) / Float(species.depth)
            direction = simd_normalize(direction)
            let next = point + direction * length / Float(segments)
            let radiusA = radius * mix(1, 0.72, Float(index) / Float(segments))
            let radiusB = radius * mix(1, 0.72, Float(index + 1) / Float(segments))
            tree.branches.append(Branch(a: point, b: next, radiusA: radiusA, radiusB: radiusB))
            point = next
        }
        tree.nodes[path] = NodeInfo(depth: depth, start: start, end: point)

        if depth >= species.depth - 1 {
            let base = depth == species.depth ? Float(species.leafCount) : Float(species.leafCount) * 0.4
            let count = max(1, Int((base * season.density + random.signed()).rounded()))
            for _ in 0..<count {
                let offset = SIMD3<Float>(random.signed(), random.signed() * 0.8, random.signed()) * species.leafSize * 2.4
                let paletteIndex = tinted ? -1 : min(Int(random.next() * Float(paletteCount)), paletteCount - 1)
                tree.leaves.append(Leaf(position: point + offset, size: species.leafSize * random.range(0.6, 1.15), rotation: random.next() * 6.28, paletteIndex: paletteIndex, shade: min(Int(random.next() * 3), 2)))
            }
        }
        if active, let difference {
            let decoration = decorationPosition(end: point, species: species)
            switch difference.kind {
            case .fruit:
                for _ in 0..<4 {
                    tree.fruits.append(Ornament(position: decoration + [random.signed() * 0.5, -0.2 - random.next() * 0.3, random.signed() * 0.5], size: 0.13 + random.next() * 0.05, rotation: 0))
                }
            case .blossom:
                for _ in 0..<9 {
                    tree.blossoms.append(Ornament(position: decoration + SIMD3<Float>(random.signed(), random.signed() * 0.7, random.signed()) * 0.9, size: 0.1 + random.next() * 0.06, rotation: random.next() * 6))
                }
            case .bird:
                tree.birds.append(Bird(position: decoration, yaw: difference.yaw, color: difference.birdColor))
            default:
                break
            }
        }
        guard depth < species.depth, tree.branches.count < 9_000 else {
            return
        }
        let childCount = species.kids + (random.next() < 0.3 ? 1 : 0)
        let reference: SIMD3<Float> = abs(direction.y) < 0.9 ? up : [1, 0, 0]
        let perpendicular = simd_normalize(simd_cross(direction, reference))
        let roll = random.next() * 6.28
        for child in 0..<childCount {
            let apical = child == 0
            let angle = apical ? species.spread * 0.25 * random.next() : species.spread * random.range(0.75, 1.3)
            let side = simd_quatf(angle: roll + Float(child) * 2.399_96, axis: direction).act(perpendicular)
            let childDirection = simd_normalize(direction * cos(angle) + side * sin(angle))
            let childLength = length * species.decay * (apical ? 1 : random.range(0.8, 1))
            let childRadius = radius * 0.72 * (apical ? 0.95 : random.range(0.7, 0.85))
            node(path: "\(path).\(child)", start: point, direction: childDirection, length: childLength, radius: childRadius, depth: depth + 1, tinted: tinted)
        }
    }

    node(path: "0", start: [0, -0.2, 0], direction: up, length: species.trunkLength, radius: species.trunkRadius, depth: 0, tinted: false)
    return tree
}

private let birdColors: [SIMD3<Float>] = [0xC8302D, 0x2F6FD1, 0xF2C230, 0x3B3B3B, 0xD9773A].map(linearColor)

func chooseDifferences(species: Species, seed: UInt32, base: GrownTree, level: Int) -> [Difference] {
    var random = SeededRandom("mut\(seed)")
    let target = min(3 + level / 2, 7)
    let paths = base.nodes.keys.sorted()
    let depth = species.depth
    let minimumDepth = level < 3 ? 2 : 3
    let kinds = DifferenceKind.allCases
    var chosen: [Difference] = []

    func conflicts(_ path: String) -> Bool {
        chosen.contains { $0.path == path || $0.path.hasPrefix(path + ".") || path.hasPrefix($0.path + ".") }
    }

    var attempts = 0
    while chosen.count < target, attempts < 2_000 {
        attempts += 1
        let kind = kinds[(chosen.count + Int(random.next() * 6)) % kinds.count]
        let candidates: [String]
        switch kind {
        case .prune, .bend:
            let lower = level < 3 ? minimumDepth : minimumDepth - 1
            candidates = paths.filter { (lower...min(minimumDepth + 1, depth - 1)).contains(base.nodes[$0]!.depth) }
        case .tint:
            candidates = paths.filter { ((depth - 3)...(depth - 2)).contains(base.nodes[$0]!.depth) }
        default:
            candidates = paths.filter { base.nodes[$0]!.depth >= depth - 1 }
        }
        guard !candidates.isEmpty else {
            continue
        }
        let path = random.pick(candidates)
        guard !conflicts(path), let info = base.nodes[path] else {
            continue
        }
        let anchor: SIMD3<Float> = switch kind {
        case .prune: simd_mix(info.start, info.end, SIMD3(repeating: 0.6))
        case .bend, .tint: info.end
        default: decorationPosition(end: info.end, species: species)
        }
        if chosen.contains(where: { simd_distance($0.anchor, anchor) < 2.2 }) {
            continue
        }
        var difference = Difference(kind: kind, side: random.next() < 0.5 ? .left : .right, path: path, anchor: anchor)
        if kind == .bend {
            let direction = simd_normalize(info.end - info.start)
            var axis = simd_cross(direction, up)
            if simd_length_squared(axis) < 0.01 {
                axis = [1, 0, 0]
            }
            difference.axis = simd_normalize(axis)
            difference.angle = (random.next() < 0.5 ? -1 : 1) * random.range(0.5, 0.75)
        }
        if kind == .bird {
            difference.yaw = random.next() * 6.28
            difference.birdColor = random.pick(birdColors)
        }
        chosen.append(difference)
    }
    return chosen
}
