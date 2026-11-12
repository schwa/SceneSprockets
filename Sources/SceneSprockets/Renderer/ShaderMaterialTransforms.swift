import MetalSprockets
import SceneSprocketsShaders
import simd

// Camera-relative rendering (#251, #253): shaders get positions with the camera at the origin, so values near the
// camera stay small and precise even far from the world origin.
package extension simd_float4x4 {
    /// Returns this transform with the camera position subtracted from its translation, computed in `Double`.
    func cameraRelative(to cameraPosition: SIMD3<Float>) -> simd_float4x4 {
        var result = self
        result.columns.3 = SIMD4(SIMD3<Float>(SIMD3<Double>(columns.3.xyz) - SIMD3<Double>(cameraPosition)), columns.3.w)
        return result
    }

    /// This view matrix without its translation, for use with ``cameraRelative(to:)`` model matrices.
    var rotationOnlyView: simd_float4x4 {
        var result = self
        result.columns.3 = [0, 0, 0, 1]
        return result
    }
}

/// Returns a position minus the camera position, computed in `Double` to keep precision far from the origin.
package func cameraRelative(_ position: SIMD3<Float>, to cameraPosition: SIMD3<Float>) -> SIMD3<Float> {
    SIMD3<Float>(SIMD3<Double>(position) - SIMD3<Double>(cameraPosition))
}

public extension ShaderMaterialTransforms {
    /// Far from the world origin, view * model cancels two large translations in Float and loses the small difference
    /// (#251). Subtracting the camera position in Double first keeps modelViewProjectionMatrix precise.
    ///
    /// With `stereoViews`, the per-view fields hold each view; `cameraPosition` is then the render origin between them.
    init(modelMatrix: simd_float4x4, viewMatrix: simd_float4x4, projectionMatrix: simd_float4x4, cameraPosition: SIMD3<Float>, opacity: Float, stereoViews: StereoViews? = nil) {
        let cameraRelativeModelMatrix = modelMatrix.cameraRelative(to: cameraPosition)
        let cameraRelativeViewMatrix = viewMatrix.rotationOnlyView
        let modelViewProjectionMatrix = projectionMatrix * cameraRelativeViewMatrix * cameraRelativeModelMatrix
        let perView = stereoViews?.relativeViewProjections(origin: cameraPosition).map { $0 * cameraRelativeModelMatrix } ?? [modelViewProjectionMatrix]
        let eyes = stereoViews?.cameraPositions.map { cameraRelative($0, to: cameraPosition) } ?? [.zero]
        self.init(
            modelMatrix: modelMatrix,
            viewMatrix: viewMatrix,
            projectionMatrix: projectionMatrix,
            modelViewProjectionMatrix: modelViewProjectionMatrix,
            normalMatrix: modelMatrix.inverse.transpose,
            cameraPosition: cameraPosition,
            opacity: opacity,
            cameraRelativeModelMatrix: cameraRelativeModelMatrix,
            cameraRelativeViewMatrix: cameraRelativeViewMatrix,
            modelViewProjectionMatrices: (perView[0], perView[min(1, perView.count - 1)]),
            cameraRelativeEyePositions: (eyes[0], eyes[min(1, eyes.count - 1)])
        )
    }
}
