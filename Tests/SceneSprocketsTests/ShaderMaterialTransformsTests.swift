import GeometryLite3D
@testable import SceneSprockets
import SceneSprocketsShaders
import simd
import Testing

private func doubleMatrix(_ matrix: simd_float4x4) -> simd_double4x4 {
    simd_double4x4(columns: (SIMD4<Double>(matrix.columns.0), SIMD4<Double>(matrix.columns.1), SIMD4<Double>(matrix.columns.2), SIMD4<Double>(matrix.columns.3)))
}

// #251: a node and camera ~100 km from the origin, 5 m apart. Clip positions must stay as precise as near the origin.
@Test
func modelViewProjectionKeepsPrecisionFarFromOrigin() {
    let origin = SIMD3<Float>(100_000, 0, 60_000)
    let modelMatrix = simd_float4x4(translation: origin + [0.25, 0.125, 0])
    let cameraMatrix = simd_float4x4(translation: origin + [0, 0, 5])
    let viewMatrix = cameraMatrix.inverse
    let projectionMatrix = PerspectiveProjection(verticalAngleOfView: .degrees(45)).projectionMatrix(aspectRatio: 1)
    let transforms = ShaderMaterialTransforms(modelMatrix: modelMatrix, viewMatrix: viewMatrix, projectionMatrix: projectionMatrix, cameraPosition: cameraMatrix.columns.3.xyz, opacity: 1)

    let reference = doubleMatrix(projectionMatrix) * doubleMatrix(cameraMatrix).inverse * doubleMatrix(modelMatrix)
    for point in [SIMD4<Float>(0, 0, 0, 1), [0.001, 0.0005, 0.002, 1], [-0.01, 0.007, 0, 1]] {
        let expected = reference * SIMD4<Double>(point)
        let actual = SIMD4<Double>(transforms.modelViewProjectionMatrix * point)
        let expectedNDC = SIMD2(expected.x, expected.y) / expected.w
        let actualNDC = SIMD2(actual.x, actual.y) / actual.w
        // 1e-5 NDC is well under a pixel at 4K.
        #expect(simd_length(expectedNDC - actualNDC) < 1e-5, "\(point): \(actualNDC) vs \(expectedNDC)")
    }

    #expect(transforms.cameraRelativeModelMatrix.columns.3 == [0.25, 0.125, -5, 1])
    let recomposed = projectionMatrix * transforms.cameraRelativeViewMatrix * transforms.cameraRelativeModelMatrix
    for column in 0..<4 {
        #expect(simd_length(recomposed[column] - transforms.modelViewProjectionMatrix[column]) < 1e-4)
    }
}
