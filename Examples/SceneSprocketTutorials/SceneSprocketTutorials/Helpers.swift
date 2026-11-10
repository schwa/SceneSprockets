import GeometryLite3D
import SceneSprockets
import SceneSprocketsBlinnPhong

extension SceneGraph.Node {
    @discardableResult
    func addShape(_ shape: SceneGraph.Shape, _ material: any SceneSprockets.Material, at position: SIMD3<Float> = .zero) -> SceneGraph.Node {
        let node = self.addChild(SceneGraph.Node(shape: shape, material: material))
        node.trs.translation = position
        return node
    }
}

func material(_ color: SIMD3<Float>, shininess: Float = 32, opacity: Float = 1, emission: SIMD3<Float> = .zero) -> BlinnPhongSceneMaterial {
    BlinnPhongSceneMaterial(ambient: .color(color * 0.3), diffuse: .color(color), specular: .color(0.5), shininess: shininess, opacity: opacity, emission: .color(emission))
}
