import GeometryLite3D
@testable import SceneSprockets
import simd
import Testing

// #367: lights, cameras and placed nodes in one expression.
@Test
func lightAndCameraFactoriesBuildPlacedNodes() throws {
    let root = SceneGraph.Node()
    let fill = root.addChild(.light(.point(intensity: 15, range: 50, castsShadow: false), label: "Fill", transform: .init(translation: [-5, 4, 4])))
    let camera = root.addChild(.camera(label: "Camera", transform: .init(translation: [0, 2, 6])))

    #expect(fill.label == "Fill")
    #expect(fill.transform.translation == [-5, 4, 4])
    guard case let .light(light) = fill.content else {
        Issue.record("Expected a light")
        return
    }
    #expect(light.type == .point)
    #expect(light.intensity == 15)
    #expect(light.range == 50)
    #expect(!light.castsShadow)

    #expect(camera.transform.translation == [0, 2, 6])
    guard case let .camera(cameraValue) = camera.content else {
        Issue.record("Expected a camera")
        return
    }
    let projection = try #require(cameraValue.projection as? PerspectiveProjection)
    #expect(abs(projection.verticalAngleOfView.degrees - 60) < 1e-4)
}

// The look-at transform matches the camera(eye:target:) / pose(eye:target:) matrix helpers in the demo and tests, and
// look(at:), so swapping them keeps scenes the same.
@Test
func lookingAtTransformMatchesCameraMatrixAndLookAt() {
    func pose(eye: SIMD3<Float>, target: SIMD3<Float>) -> simd_float4x4 {
        let forward = simd_normalize(eye - target)
        let right = simd_normalize(simd_cross([0, 1, 0], forward))
        return simd_float4x4(columns: (SIMD4(right, 0), SIMD4(simd_cross(forward, right), 0), SIMD4(forward, 0), SIMD4(eye, 1)))
    }
    for (eye, target) in [(SIMD3<Float>(0, 3, 8), SIMD3<Float>(0, 0.5, 0)), ([3, 7, 3], .zero), ([-5, 4, 4], [1, 0, -2])] {
        let transform = Transform3D(position: eye, lookingAt: target)
        #expect(transform.matrix.isApproximatelyEqual(to: pose(eye: eye, target: target), absoluteTolerance: 1e-5))
        let node = SceneGraph.Node(transform: .init(translation: eye))
        node.look(at: target)
        #expect(transform.matrix.isApproximatelyEqual(to: node.transform.matrix, absoluteTolerance: 1e-5))
    }
}

@Test
func lightFactoriesSetTypeAndShadows() {
    #expect(Light.directional(intensity: 2).type == .directional)
    #expect(Light.directional(intensity: 2).intensity == 2)
    #expect(Light.point().type == .point)
    #expect(!Light.spot(castsShadow: false).castsShadow)
    #expect(Light.spot().castsShadow)
}

@Test
func cameraFactories() throws {
    let perspective = try #require(Camera.perspective(fieldOfView: .degrees(45), zClip: 0.1 ... 50).projection as? PerspectiveProjection)
    #expect(abs(perspective.verticalAngleOfView.degrees - 45) < 1e-4)
    #expect(perspective.depthMode == .standard(zClip: 0.1 ... 50))
    let orthographic = try #require(Camera.orthographic(halfHeight: 3).projection as? OrthographicProjection)
    #expect(orthographic.halfHeight == 3)
    #expect(Camera.default.projection is PerspectiveProjection)
}
