import SceneSprocketsShaders
import simd

public extension ShaderMaterialTransforms {
    // Far from the world origin, view * model cancels two large translations in Float and loses the small difference
    // (#251). Subtracting the camera position in Double first keeps modelViewProjectionMatrix precise.
    init(modelMatrix: simd_float4x4, viewMatrix: simd_float4x4, projectionMatrix: simd_float4x4, cameraPosition: SIMD3<Float>, opacity: Float) {
        let relativeTranslation = SIMD3<Double>(modelMatrix.columns.3.xyz) - SIMD3<Double>(cameraPosition)
        var cameraRelativeModelMatrix = modelMatrix
        cameraRelativeModelMatrix.columns.3 = SIMD4(SIMD3<Float>(relativeTranslation), 1)
        var cameraRelativeViewMatrix = viewMatrix
        cameraRelativeViewMatrix.columns.3 = [0, 0, 0, 1]
        self.init(
            modelMatrix: modelMatrix,
            viewMatrix: viewMatrix,
            projectionMatrix: projectionMatrix,
            modelViewProjectionMatrix: projectionMatrix * cameraRelativeViewMatrix * cameraRelativeModelMatrix,
            normalMatrix: modelMatrix.inverse.transpose,
            cameraPosition: cameraPosition,
            opacity: opacity,
            cameraRelativeModelMatrix: cameraRelativeModelMatrix,
            cameraRelativeViewMatrix: cameraRelativeViewMatrix
        )
    }
}
