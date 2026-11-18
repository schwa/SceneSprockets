import Metal
import SceneSprockets

// CI runners have a paravirtual GPU without Metal 4.
let deviceSupportsMetal4 = MTLCreateSystemDefaultDevice()?.supportsFamily(.metal4) ?? false

extension SceneGraph {
    // For tests that check exact shaded colors: clamped, without the default PBR Neutral tone mapping.
    convenience init(linearRoot root: Node) {
        self.init(root: root)
        environment.toneMapping = .linear
    }
}
