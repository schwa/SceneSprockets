import SceneSprockets
import SceneSprocketsBlinnPhong

func material(_ color: SIMD3<Float>, shininess: Float = 32, opacity: Float = 1, emission: SIMD3<Float> = .zero) -> BlinnPhongSceneMaterial {
    BlinnPhongSceneMaterial(ambient: .color(color * 0.3), diffuse: .color(color), specular: .color(0.5), shininess: shininess, opacity: opacity, emission: .color(emission))
}
