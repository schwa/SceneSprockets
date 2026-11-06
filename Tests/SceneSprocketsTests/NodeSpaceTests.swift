import GeometryLite3D
@testable import SceneSprockets
import simd
import Testing

private func isClose(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Bool {
    simd_distance(a, b) < 1e-4
}

private func makeHierarchy() -> (parent: SceneGraph.Node, child: SceneGraph.Node) {
    let parent = SceneGraph.Node(trs: .init(translation: [10, 0, 0], rotation: simd_quatf(angle: .pi / 2, axis: [0, 1, 0]), scale: [2, 2, 2]))
    let child = SceneGraph.Node(parent: parent, trs: .init(translation: [1, 0, 0]))
    return (parent, child)
}

@Test
func worldPositionRoundTrips() {
    let (parent, child) = makeHierarchy()
    withExtendedLifetime(parent) {
        // Parent turns +X onto -Z and doubles it.
        #expect(isClose(child.worldPosition, [10, 0, -2]))
        child.worldPosition = [0, 5, 0]
        #expect(isClose(child.worldPosition, [0, 5, 0]))
        guard case .trs = child.localTransform else {
            Issue.record("TRS node became a matrix node")
            return
        }
    }
}

@Test
func worldTransformSetterKeepsMatrixNodes() {
    let parent = SceneGraph.Node(transform: .init(translation: [0, 3, 0]))
    let child = SceneGraph.Node(parent: parent)
    child.worldTransform = .init(translation: [1, 1, 1])
    #expect(isClose(child.transform.columns.3.xyz, [1, -2, 1]))
    guard case .matrix = child.localTransform else {
        Issue.record("matrix node became a TRS node")
        return
    }
}

@Test
func worldTransformSetterAccountsForPivot() {
    let node = SceneGraph.Node()
    node.pivot = .init(translation: [0, 1, 0])
    node.worldTransform = .init(translation: [5, 0, 0])
    #expect(isClose(node.worldTransform.columns.3.xyz, [5, 0, 0]))
}

@Test
func worldOrientationRoundTrips() {
    let (parent, child) = makeHierarchy()
    let target = simd_quatf(angle: .pi / 3, axis: simd_normalize([1, 1, 0]))
    withExtendedLifetime(parent) {
        child.worldOrientation = target
        #expect(abs(simd_dot(child.worldOrientation.vector, target.vector)) > 0.9999)
    }
}

@Test
func eulerAnglesRoundTrip() {
    let node = SceneGraph.Node()
    // ZYX: yaw about Z, then pitch about Y, then roll about X.
    let rotation = simd_quatf(angle: 0.3, axis: [0, 0, 1]) * simd_quatf(angle: 0.2, axis: [0, 1, 0]) * simd_quatf(angle: 0.1, axis: [1, 0, 0])
    node.eulerAngles = Euler(rotation)
    #expect(abs(simd_dot(node.trs.rotation.vector, rotation.vector)) > 0.9999)
    #expect(abs(node.eulerAngles.roll - 0.1) < 1e-4)
    #expect(abs(node.eulerAngles.pitch - 0.2) < 1e-4)
    #expect(abs(node.eulerAngles.yaw - 0.3) < 1e-4)
}

@Test
func convertsBetweenNodes() {
    let (parent, child) = makeHierarchy()
    #expect(isClose(child.convertPosition(.zero, to: nil), child.worldPosition))
    #expect(isClose(parent.convertPosition(.zero, from: child), [1, 0, 0]))
    #expect(isClose(child.convertPosition(child.worldPosition, from: nil), .zero))
    #expect(isClose(parent.convertVector([1, 0, 0], to: nil), [0, 0, -2]))
    #expect(isClose(parent.convertVector([0, 0, -2], from: nil), [1, 0, 0]))
    let transform = child.convertTransform(.identity, to: parent)
    #expect(isClose(transform.columns.3.xyz, [1, 0, 0]))
    #expect(isClose(child.convertTransform(transform, from: parent).columns.3.xyz, .zero))
}

@Test
func lookAtPointsFront() {
    let (parent, child) = makeHierarchy()
    let target: SIMD3<Float> = [10, 0, 5]
    withExtendedLifetime(parent) {
        child.look(at: target)
        let front = simd_normalize(child.convertVector([0, 0, -1], to: nil))
        #expect(isClose(front, simd_normalize(target - child.worldPosition)))
    }
}
