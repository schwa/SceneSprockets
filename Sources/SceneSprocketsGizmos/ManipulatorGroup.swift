import MetalSprockets
import SceneSprockets

/// Several manipulators as one, for `SceneView`'s `sceneManipulator(_:)`, which takes one: for example a
/// ``PathPointGizmo`` over a ``TransformGizmo`` (#619).
///
/// All of them draw, in order. A drag or gesture goes to the first that claims it.
@MainActor
public final class ManipulatorGroup: ViewManipulator {
    /// The manipulators, first to claim first.
    public var manipulators: [any ViewManipulator]
    // The one that claimed the current drag or gesture.
    private var active: (any ViewManipulator)?

    public init(_ manipulators: [any ViewManipulator]) {
        self.manipulators = manipulators
    }

    public func overlay(viewport: Viewport) throws -> AnyElement? {
        let overlays = try manipulators.compactMap { try $0.overlay(viewport: viewport) }
        guard overlays.count > 1 else {
            return overlays.first
        }
        return try Group {
            ForEach(Array(overlays.indices), id: \.self) { index in
                overlays[index]
            }
        }
        .eraseToAnyElement()
    }

    // Every manipulator's hit test runs, so each updates its hover state; the first that claims wins.
    public func hitTest(_ point: SIMD2<Float>, viewport: Viewport) -> Bool {
        var claimed = false
        for manipulator in manipulators where manipulator.hitTest(point, viewport: viewport) {
            claimed = true
        }
        return claimed
    }

    public func beginDrag(at point: SIMD2<Float>, viewport: Viewport) {
        active = manipulators.first { $0.hitTest(point, viewport: viewport) }
        active?.beginDrag(at: point, viewport: viewport)
    }

    public func drag(to point: SIMD2<Float>, viewport: Viewport) {
        active?.drag(to: point, viewport: viewport)
    }

    public func endDrag() {
        active?.endDrag()
        active = nil
    }

    public func claimsTwoFingerGesture(at point: SIMD2<Float>, viewport: Viewport) -> Bool {
        active = manipulators.first { $0.claimsTwoFingerGesture(at: point, viewport: viewport) }
        return active != nil
    }

    public func beginTwoFingerGesture(viewport: Viewport) {
        active?.beginTwoFingerGesture(viewport: viewport)
    }

    public func twoFingerGesture(scale: Float, rotation: Float, viewport: Viewport) {
        active?.twoFingerGesture(scale: scale, rotation: rotation, viewport: viewport)
    }

    public func endTwoFingerGesture() {
        active?.endTwoFingerGesture()
        active = nil
    }
}
