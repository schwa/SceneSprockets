import simd

extension SceneGraph {
    // A reusable description of a change over time, like SceneKit's SCNAction. Run it with `Node.run(_:forKey:)`
    // and advance all running actions with `SceneGraph.advanceActions(by:)`.
    // Not supported: fade actions (nodes have no opacity).
    public struct Action {
        public enum TimingMode: Sendable {
            case linear
            case easeIn
            case easeOut
            case easeInEaseOut
            // Maps elapsed fraction (0...1) to progress, like SCNAction.timingFunction. Should map 0 to 0 and 1 to 1.
            case custom(@Sendable (Float) -> Float)

            func apply(_ fraction: Float) -> Float {
                switch self {
                case .linear:
                    fraction
                case .easeIn:
                    fraction * fraction
                case .easeOut:
                    1 - (1 - fraction) * (1 - fraction)
                case .easeInEaseOut:
                    fraction * fraction * (3 - 2 * fraction)
                case .custom(let function):
                    function(fraction)
                }
            }

            // The timing that plays this one backwards.
            var reversed: Self {
                switch self {
                case .linear, .easeInEaseOut:
                    self
                case .easeIn:
                    .easeOut
                case .easeOut:
                    .easeIn
                case .custom(let function):
                    .custom { 1 - function(1 - $0) }
                }
            }
        }

        // Nil for actions that repeat forever. Not changed by `speed`.
        public let duration: Float?
        // Changes how interval actions progress over their duration. Ignored by sequences, groups and repeats.
        public var timingMode: TimingMode = .linear
        // Multiplies the time this action advances by; 2 runs it twice as fast, 0 pauses it.
        public var speed: Float = 1
        fileprivate let makeRunner: (TimingMode) -> any ActionRunner
        // Nil for actions that cannot be reversed (absolute ones such as move(to:)); reversed() returns them as is.
        fileprivate var makeReversed: (() -> Action)?

        fileprivate init(duration: Float?, makeRunner: @escaping (TimingMode) -> any ActionRunner, reversed: (() -> Action)? = nil) {
            self.duration = duration
            self.makeRunner = makeRunner
            self.makeReversed = reversed
        }

        public func timingMode(_ mode: TimingMode) -> Self {
            var copy = self
            copy.timingMode = mode
            return copy
        }

        public func speed(_ speed: Float) -> Self {
            var copy = self
            copy.speed = speed
            return copy
        }

        // Plays this action backwards, like SCNAction.reversed(). Relative actions (move, rotate and scale by,
        // hide/unhide) and composites of them reverse; absolute and custom actions are returned unchanged.
        public func reversed() -> Self {
            guard let makeReversed else {
                return self
            }
            var result = makeReversed()
            result.timingMode = timingMode.reversed
            result.speed = speed
            return result
        }

        // MARK: Interval actions

        // `apply(node, from, to)` applies the progress between two eased fractions in 0...1.
        fileprivate static func interval(_ duration: Float, start: @escaping (Node) -> Void = { _ in }, reversed: (() -> Action)? = nil, apply: @escaping (Node, Float, Float) -> Void) -> Self {
            Self(duration: max(duration, 0), makeRunner: { timing in
                IntervalRunner(duration: max(duration, 0), timing: timing, start: start, apply: apply)
            }, reversed: reversed)
        }

        public static func move(by delta: SIMD3<Float>, duration: Float) -> Self {
            interval(duration, reversed: { .move(by: -delta, duration: duration) }) { node, from, to in
                node.trs.translation += delta * (to - from)
            }
        }

        public static func move(to target: SIMD3<Float>, duration: Float) -> Self {
            let start = Box<SIMD3<Float>>()
            return interval(duration, start: { start.value = $0.trs.translation }) { node, _, to in
                node.trs.translation = simd_mix(start.value ?? target, target, SIMD3(repeating: to))
            }
        }

        // Rotates in the node's parent space, about `axis` through the node's origin.
        public static func rotate(by angle: Float, around axis: SIMD3<Float>, duration: Float) -> Self {
            let axis = simd_normalize(axis)
            return interval(duration, reversed: { .rotate(by: -angle, around: axis, duration: duration) }) { node, from, to in
                node.trs.rotation = simd_normalize(simd_quatf(angle: angle * (to - from), axis: axis) * node.trs.rotation)
            }
        }

        // Rotates by Euler angles in radians, like SCNAction.rotateBy(x:y:z:duration:): about the parent's X, then Y,
        // then Z axes, through the node's origin.
        public static func rotateBy(x: Float, y: Float, z: Float, duration: Float) -> Self {
            interval(duration, reversed: { .rotateBy(x: -x, y: -y, z: -z, duration: duration) }) { node, from, to in
                let step = to - from
                node.trs.rotation = simd_normalize(eulerRotation(x: x * step, y: y * step, z: z * step) * node.trs.rotation)
            }
        }

        // Rotates to Euler angles in radians (X, then Y, then Z), like SCNAction.rotateTo(x:y:z:duration:).
        public static func rotateTo(x: Float, y: Float, z: Float, duration: Float) -> Self {
            rotate(to: eulerRotation(x: x, y: y, z: z), duration: duration)
        }

        public static func rotate(to target: simd_quatf, duration: Float) -> Self {
            let start = Box<simd_quatf>()
            return interval(duration, start: { start.value = $0.trs.rotation }) { node, _, to in
                node.trs.rotation = simd_slerp(start.value ?? target, target, to)
            }
        }

        public static func scale(by factor: Float, duration: Float) -> Self {
            interval(duration, reversed: { .scale(by: 1 / factor, duration: duration) }) { node, from, to in
                // Multiplicative, so the total over the duration is exactly `factor`.
                node.trs.scale *= pow(factor, to - from)
            }
        }

        public static func scale(to target: SIMD3<Float>, duration: Float) -> Self {
            let start = Box<SIMD3<Float>>()
            return interval(duration, start: { start.value = $0.trs.scale }) { node, _, to in
                node.trs.scale = simd_mix(start.value ?? target, target, SIMD3(repeating: to))
            }
        }

        public static func wait(duration: Float) -> Self {
            interval(duration, reversed: { .wait(duration: duration) }) { _, _, _ in }
        }

        // Waits a random time in duration ± range / 2 (never below 0), picked each time it starts. `duration` reports
        // the average.
        public static func wait(duration: Float, withRange range: Float) -> Self {
            Self(duration: max(duration, 0), makeRunner: { timing in
                let picked = max(duration + Float.random(in: -0.5...0.5) * range, 0)
                return IntervalRunner(duration: picked, timing: timing, start: { _ in }, apply: { _, _, _ in })
            }, reversed: { .wait(duration: duration, withRange: range) })
        }

        // `body` gets the node and the time since the action started, clamped to `duration`.
        public static func custom(duration: Float, _ body: @escaping (Node, Float) -> Void) -> Self {
            interval(duration) { node, _, to in
                body(node, to * max(duration, 0))
            }
        }

        // MARK: Instant actions

        public static func run(_ body: @escaping (Node) -> Void) -> Self {
            interval(0) { node, _, _ in body(node) }
        }

        public static func hide() -> Self {
            var action = run { $0.isVisible = false }
            action.makeReversed = { .unhide() }
            return action
        }

        public static func unhide() -> Self {
            var action = run { $0.isVisible = true }
            action.makeReversed = { .hide() }
            return action
        }

        public static func removeFromParent() -> Self {
            run { $0.removeFromParent() }
        }

        // MARK: Composite actions

        public static func sequence(_ actions: [Action]) -> Self {
            let total = actions.reduce(Float?(0)) { sum, action in
                guard let sum, let duration = action.duration else { return nil }
                return sum + duration
            }
            return Self(duration: total, makeRunner: { _ in SequenceRunner(actions: actions) }, reversed: { .sequence(actions.reversed().map { $0.reversed() }) })
        }

        public static func group(_ actions: [Action]) -> Self {
            let total = actions.reduce(Float?(0)) { longest, action in
                guard let longest, let duration = action.duration else { return nil }
                return max(longest, duration)
            }
            return Self(duration: total, makeRunner: { _ in GroupRunner(actions: actions) }, reversed: { .group(actions.map { $0.reversed() }) })
        }

        public static func `repeat`(_ action: Action, count: Int) -> Self {
            Self(duration: action.duration.map { $0 * Float(max(count, 0)) }, makeRunner: { _ in RepeatRunner(action: action, count: max(count, 0)) }, reversed: { .repeat(action.reversed(), count: count) })
        }

        public static func repeatForever(_ action: Action) -> Self {
            Self(duration: nil, makeRunner: { _ in RepeatRunner(action: action, count: nil) }, reversed: { .repeatForever(action.reversed()) })
        }

        fileprivate func runner() -> any ActionRunner {
            let runner = makeRunner(timingMode)
            return speed == 1 ? runner : SpeedRunner(runner: runner, speed: speed)
        }
    }

    // Advances every running action in the graph, including on hidden nodes.
    public func advanceActions(by deltaTime: Float) {
        var nodes: [Node] = []
        visit(includeHidden: true) { node, _ in
            if !node.runningActions.isEmpty {
                nodes.append(node)
            }
        }
        for node in nodes {
            node.advanceActions(by: deltaTime)
        }
    }
}

extension SceneGraph.Node {
    final class RunningAction {
        let key: String?
        let action: SceneGraph.Action
        let runner: any ActionRunner
        let completion: (() -> Void)?

        init(key: String?, action: SceneGraph.Action, completion: (() -> Void)?) {
            self.key = key
            self.action = action
            self.runner = action.runner()
            self.completion = completion
        }
    }

    // Starts `action` on this node. An action with the same key is removed first.
    public func run(_ action: SceneGraph.Action, forKey key: String? = nil, completion: (() -> Void)? = nil) {
        if let key {
            removeAction(forKey: key)
        }
        runningActions.append(RunningAction(key: key, action: action, completion: completion))
    }

    // The running action started with `key`, like SCNNode.action(forKey:).
    public func action(forKey key: String) -> SceneGraph.Action? {
        runningActions.first { $0.key == key }?.action
    }

    public func removeAction(forKey key: String) {
        runningActions.removeAll { $0.key == key }
    }

    public func removeAllActions() {
        runningActions.removeAll()
    }

    public var hasActions: Bool {
        !runningActions.isEmpty
    }

    public func hasAction(forKey key: String) -> Bool {
        runningActions.contains { $0.key == key }
    }

    func advanceActions(by deltaTime: Float) {
        let deltaTime = deltaTime * actionSpeed
        for running in runningActions {
            // An earlier action or completion may have removed this one.
            guard runningActions.contains(where: { $0 === running }) else {
                continue
            }
            if running.runner.step(self, deltaTime) != nil {
                runningActions.removeAll { $0 === running }
                running.completion?()
            }
        }
    }
}

// Returns nil while running, or the part of `deltaTime` left over once finished.
protocol ActionRunner: AnyObject {
    func step(_ node: SceneGraph.Node, _ deltaTime: Float) -> Float?
}

private final class Box<Value> {
    var value: Value?
}

// X, then Y, then Z, about fixed axes.
private func eulerRotation(x: Float, y: Float, z: Float) -> simd_quatf {
    simd_quatf(angle: z, axis: [0, 0, 1]) * simd_quatf(angle: y, axis: [0, 1, 0]) * simd_quatf(angle: x, axis: [1, 0, 0])
}

// Runs another runner with scaled time. Leftover time is scaled back, so what follows runs at its own speed.
private final class SpeedRunner: ActionRunner {
    let runner: any ActionRunner
    let speed: Float

    init(runner: any ActionRunner, speed: Float) {
        self.runner = runner
        self.speed = speed
    }

    func step(_ node: SceneGraph.Node, _ deltaTime: Float) -> Float? {
        guard speed > 0 else {
            return nil
        }
        return runner.step(node, deltaTime * speed).map { $0 / speed }
    }
}

private final class IntervalRunner: ActionRunner {
    let duration: Float
    let timing: SceneGraph.Action.TimingMode
    let start: (SceneGraph.Node) -> Void
    let apply: (SceneGraph.Node, Float, Float) -> Void
    var elapsed: Float = 0
    var fraction: Float = 0
    var started = false

    init(duration: Float, timing: SceneGraph.Action.TimingMode, start: @escaping (SceneGraph.Node) -> Void, apply: @escaping (SceneGraph.Node, Float, Float) -> Void) {
        self.duration = duration
        self.timing = timing
        self.start = start
        self.apply = apply
    }

    func step(_ node: SceneGraph.Node, _ deltaTime: Float) -> Float? {
        if !started {
            started = true
            start(node)
        }
        elapsed += deltaTime
        let progress = duration > 0 ? min(elapsed / duration, 1) : 1
        let next = timing.apply(progress)
        apply(node, fraction, next)
        fraction = next
        return elapsed >= duration ? elapsed - duration : nil
    }
}

private final class SequenceRunner: ActionRunner {
    let actions: [SceneGraph.Action]
    var index = 0
    var current: (any ActionRunner)?

    init(actions: [SceneGraph.Action]) {
        self.actions = actions
    }

    func step(_ node: SceneGraph.Node, _ deltaTime: Float) -> Float? {
        var remaining = deltaTime
        while index < actions.count {
            let runner = current ?? actions[index].runner()
            current = runner
            guard let leftover = runner.step(node, remaining) else {
                return nil
            }
            remaining = leftover
            index += 1
            current = nil
        }
        return remaining
    }
}

private final class GroupRunner: ActionRunner {
    var runners: [(runner: any ActionRunner, leftover: Float?)]

    init(actions: [SceneGraph.Action]) {
        runners = actions.map { ($0.runner(), nil) }
    }

    func step(_ node: SceneGraph.Node, _ deltaTime: Float) -> Float? {
        for index in runners.indices where runners[index].leftover == nil {
            runners[index].leftover = runners[index].runner.step(node, deltaTime)
        }
        let leftovers = runners.map(\.leftover)
        guard leftovers.allSatisfy({ $0 != nil }) else {
            return nil
        }
        // The longest child finished last, with the least time left over.
        return leftovers.compactMap(\.self).min() ?? deltaTime
    }
}

private final class RepeatRunner: ActionRunner {
    let action: SceneGraph.Action
    let count: Int?
    var completed = 0
    var current: (any ActionRunner)?

    init(action: SceneGraph.Action, count: Int?) {
        self.action = action
        self.count = count
    }

    func step(_ node: SceneGraph.Node, _ deltaTime: Float) -> Float? {
        var remaining = deltaTime
        // Bounded, so a zero-length action repeated forever runs once per step instead of hanging.
        for _ in 0..<1000 {
            if let count, completed >= count {
                return remaining
            }
            let runner = current ?? action.runner()
            current = runner
            guard let leftover = runner.step(node, remaining) else {
                return nil
            }
            completed += 1
            current = nil
            remaining = leftover
            if count == nil, (action.duration ?? 0) <= 0 {
                return nil
            }
        }
        return nil
    }
}
