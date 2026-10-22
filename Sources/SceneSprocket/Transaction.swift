import GeometryLite3D
import simd

extension SceneGraph {
    // Implicit animation, like SCNTransaction: transform and morph weight changes made in `body` animate from their
    // old values over `duration` instead of jumping. Animations run as node actions (keys "implicit.transform" and
    // "implicit.morphWeights"), so they need `SceneGraph.advanceActions(by:)` each frame (SceneView does this).
    // A new implicit animation of the same property replaces the running one, starting from the current value.
    public enum Transaction {
        @TaskLocal static var current: Recorder?

        public static func animate(duration: Float, timingMode: Action.TimingMode = .easeInEaseOut, _ body: () throws -> Void, completion: (() -> Void)? = nil) rethrows {
            guard duration > 0 else {
                try body()
                completion?()
                return
            }
            let recorder = Recorder()
            try $current.withValue(recorder) {
                try body()
            }
            recorder.start(duration: duration, timingMode: timingMode, completion: completion)
        }

        // Changes made in `body` apply at once, even inside an animating transaction.
        public static func withoutAnimation(_ body: () throws -> Void) rethrows {
            try $current.withValue(nil) {
                try body()
            }
        }
    }
}

extension SceneGraph.Transaction {
    // Collects the first old value of each changed property. Only used on the thread that runs the transaction.
    final class Recorder: @unchecked Sendable {
        private var transforms: [(node: SceneGraph.Node, from: Transform3D)] = []
        private var morphWeights: [(node: SceneGraph.Node, from: [Float])] = []

        func recordTransform(of node: SceneGraph.Node, oldValue: SceneGraph.LocalTransform) {
            guard !transforms.contains(where: { $0.node === node }) else {
                return
            }
            transforms.append((node, oldValue.trs))
        }

        func recordMorphWeights(of node: SceneGraph.Node, oldValue: [Float]) {
            guard !morphWeights.contains(where: { $0.node === node }) else {
                return
            }
            morphWeights.append((node, oldValue))
        }

        // Puts every changed property back to its old value and animates it to the new one.
        func start(duration: Float, timingMode: SceneGraph.Action.TimingMode, completion: (() -> Void)?) {
            let total = transforms.count + morphWeights.count
            guard total > 0 else {
                completion?()
                return
            }
            var remaining = total
            let finished = {
                remaining -= 1
                if remaining == 0 {
                    completion?()
                }
            }
            for (node, from) in transforms {
                let to = node.trs
                node.trs = from
                let action = SceneGraph.Action.custom(duration: duration) { node, elapsed in
                    let t = timingMode.apply(min(elapsed / duration, 1))
                    node.trs = from.interpolated(to: to, amount: t)
                }
                node.run(action, forKey: "implicit.transform", completion: finished)
            }
            for (node, from) in morphWeights {
                let to = node.morphWeights
                node.morphWeights = from
                let action = SceneGraph.Action.custom(duration: duration) { node, elapsed in
                    let t = timingMode.apply(min(elapsed / duration, 1))
                    node.morphWeights = (0..<max(from.count, to.count)).map { index in
                        let start = index < from.count ? from[index] : 0
                        let end = index < to.count ? to[index] : 0
                        return start + (end - start) * t
                    }
                }
                node.run(action, forKey: "implicit.morphWeights", completion: finished)
            }
        }
    }
}
