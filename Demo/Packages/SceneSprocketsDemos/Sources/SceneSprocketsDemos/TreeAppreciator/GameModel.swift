import Foundation
import GeometryLite3D
import Metal
import Observation
import QuartzCore
import SceneSprockets
import SceneSprocketsBlinnPhong
import simd

@MainActor
@Observable
final class GameModel {
    static let levelNames = ["Siblings", "Twins", "Neighbours", "Old friends", "Echoes", "Reflections", "Cousins", "Rivals", "Strangers", "Lovers"]
    static let treeNames = ["the elder", "the younger", "the dreamer", "the quiet one", "the stubborn one", "the listener"]

    let device = MTLCreateSystemDefaultDevice()!
    let chimes = Chimes()

    private(set) var level = 0
    private(set) var levelID = UUID()
    private(set) var left: World?
    private(set) var right: World?
    private(set) var differences: [Difference] = []
    private(set) var leftName = ""
    private(set) var rightName = ""
    private(set) var score = 0
    private(set) var squints = 0
    private(set) var hints = 0
    private(set) var isComplete = false
    private(set) var completionBonus = 0
    private(set) var caption: String?
    private(set) var cameraTarget: SIMD3<Float> = [0, 4, 0]
    var cameraMatrix: simd_float4x4?
    var showsIntro = true
    var isMuted = false {
        didSet { chimes.isMuted = isMuted }
    }

    private var streak = 0
    private var captionTask: Task<Void, Never>?
    @ObservationIgnored let clockStart = CACurrentMediaTime()
    @ObservationIgnored let swayDriver = SwayDriver()

    private(set) var season = Season.all[0]
    private let firstSeason = Int.random(in: 0..<Season.all.count)

    var foundCount: Int {
        differences.filter(\.found).count
    }

    init() {
        newPair()
    }

    func begin() {
        showsIntro = false
        chimes.start()
    }

    func nextPair() {
        level += 1
        newPair()
    }

    func skipPair() {
        streak = 0
        newPair()
    }

    func newPair() {
        let seed = UInt32.random(in: 0...UInt32.max)
        let season = Season.all[(firstSeason + level) % Season.all.count].dressed(seed: seed)
        self.season = season
        let species = Species(seed: seed)
        let base = growTree(species: species, seed: seed, season: season, differences: [:], side: nil)
        let chosen = chooseDifferences(species: species, seed: seed, base: base, level: level)
        let byPath = Dictionary(uniqueKeysWithValues: chosen.map { ($0.path, $0) })
        let leftTree = growTree(species: species, seed: seed, season: season, differences: byPath, side: .left)
        let rightTree = growTree(species: species, seed: seed, season: season, differences: byPath, side: .right)
        left = makeWorld(tree: leftTree, species: species, season: season, seed: seed, device: device)
        right = makeWorld(tree: rightTree, species: species, season: season, seed: seed, device: device)
        swayDriver.trees = [left!.treeNode, right!.treeNode]
        differences = chosen
        squints = 0
        hints = 0
        isComplete = false
        completionBonus = 0

        var lower = SIMD3<Float>(0, 0, 0)
        var upper = SIMD3<Float>(0, 0, 0)
        for leaf in base.leaves {
            lower = simd_min(lower, leaf.position)
            upper = simd_max(upper, leaf.position)
        }
        for branch in base.branches {
            lower = simd_min(lower, branch.b)
            upper = simd_max(upper, branch.b)
        }
        let size = upper - lower
        cameraTarget = (lower + upper) / 2
        // Each view is about half the window wide, so fit height and width.
        let halfAngle: Float = .pi / 6
        let distance = max(size.y * 0.66, max(size.x, size.z) * 0.62 / 0.75) / tan(halfAngle) * 1.3 + 2
        let azimuth: Float = 0.3
        let eye = cameraTarget + SIMD3<Float>(sin(azimuth) * cos(0.12), sin(0.12), cos(azimuth) * cos(0.12)) * distance
        cameraMatrix = LookAt(position: eye, target: cameraTarget, up: [0, 1, 0]).cameraMatrix

        var random = SeededRandom(seed: seed)
        leftName = random.pick(Self.treeNames)
        repeat { rightName = random.pick(Self.treeNames) } while rightName == leftName
        levelID = UUID()
    }

    // `point` and `viewport` come from the tapped side's SceneView.
    func tap(side: Side, point: SIMD2<Float>, viewport: SceneViewport) {
        guard !isComplete, !showsIntro, let world = side == .left ? left : right else {
            return
        }
        let threshold = max(30, viewport.viewSize.y * 0.075)
        var best: (index: Int, distance: Float)?
        for (index, difference) in differences.enumerated() where !difference.found {
            let world = world.treeNode.worldTransform.transformPoint(difference.anchor)
            guard let projected = viewport.project(world) else {
                continue
            }
            let distance = simd_distance(SIMD2(projected.x, projected.y), point)
            if distance < (best?.distance ?? .infinity) {
                best = (index, distance)
            }
        }
        if let best, best.distance < threshold {
            differences[best.index].found = true
            streak += 1
            score += 100 + 20 * (streak - 1)
            chimes.found(foundCount * 2)
            addRing(for: differences[best.index], hint: false)
            let difference = differences[best.index]
            var line = difference.kind.captions.randomElement() ?? ""
            line = line.replacingOccurrences(of: "{w}", with: season.tintWord)
            show(caption: line)
            if foundCount == differences.count {
                Task {
                    try? await Task.sleep(for: .seconds(1.4))
                    complete()
                }
            }
        } else {
            squints += 1
            streak = 0
            score = max(0, score - 10)
            chimes.miss()
        }
    }

    func hint() {
        guard !isComplete, let difference = differences.filter({ !$0.found }).randomElement() else {
            return
        }
        hints += 1
        streak = 0
        score = max(0, score - 40)
        addRing(for: difference, hint: true)
        chimes.hint()
        show(caption: "Look somewhere around here…")
    }

    private func complete() {
        isComplete = true
        completionBonus = max(0, 150 - squints * 15 - hints * 40)
        score += completionBonus
        chimes.complete()
    }

    var verdict: String {
        if squints == 0, hints == 0 {
            return "A flawless eye. The trees feel seen."
        }
        if squints < 4 {
            return "A patient, careful look."
        }
        return "You looked long, and that is its own kind of love."
    }

    private func show(caption: String) {
        self.caption = caption
        captionTask?.cancel()
        captionTask = Task {
            try? await Task.sleep(for: .seconds(3.2))
            if !Task.isCancelled {
                self.caption = nil
            }
        }
    }

    private func addRing(for difference: Difference, hint: Bool) {
        for world in [left, right].compactMap(\.self) {
            let jitter: SIMD3<Float> = hint ? SIMD3(Float.random(in: -1...1), Float.random(in: -1...1), Float.random(in: -1...1)) : .zero
            let holder = SceneGraph.Node(parent: world.treeNode, label: hint ? "Hint" : "Ring", trs: Transform3D(translation: difference.anchor + jitter))
            holder.constraints = [.billboard()]
            let radius: Float = hint ? 2.4 : 0.9
            let color: SIMD3<Float> = hint ? [1.2, 1.2, 1.2] : [1.6, 1.15, 0.45]
            let ring = SceneGraph.Node(parent: holder, label: "Torus", shape: .torus(ringRadius: radius, pipeRadius: hint ? 0.04 : 0.07), material: glowing(color), device: device, trs: Transform3D(rotation: simd_quatf(angle: .pi / 2, axis: [1, 0, 0])))
            ring.content = ring.content.withoutShadows
            holder.trs.scale = SIMD3(repeating: 0.01)
            if hint {
                holder.run(.sequence([
                    .custom(duration: 3.5) { node, elapsed in
                        let t = elapsed / 3.5
                        node.trs.scale = SIMD3(repeating: sin(t * .pi) * (1 + 0.08 * sin(elapsed * 6)))
                    },
                    .removeFromParent(),
                ]))
            } else {
                holder.run(.custom(duration: 0.6) { node, elapsed in
                    let t = elapsed / 0.6
                    node.trs.scale = SIMD3(repeating: t + sin(t * .pi) * 0.5)
                })
            }
        }
    }
}

extension SceneGraph.Node.Content {
    var withoutShadows: Self {
        if case let .mesh(mesh, materials, _, _) = self {
            return .mesh(mesh, materials: materials, castsShadow: false, receivesShadow: false)
        }
        return self
    }
}

// Rocks both trees with the same wall-clock time so the wind never creates a fake difference.
@MainActor
final class SwayDriver: SceneViewDelegate {
    var trees: [SceneGraph.Node] = []
    private let start = CACurrentMediaTime()

    func sceneView(updateAtTime time: Float, deltaTime: Float) {
        let t = Float(CACurrentMediaTime() - start)
        let rotation = simd_quatf(angle: 0.012 * sin(t * 1.1) + 0.005 * sin(t * 2.3), axis: [0, 0, 1])
            * simd_quatf(angle: 0.008 * cos(t * 0.8), axis: [1, 0, 0])
        for tree in trees {
            tree.trs.rotation = rotation
        }
    }
}
