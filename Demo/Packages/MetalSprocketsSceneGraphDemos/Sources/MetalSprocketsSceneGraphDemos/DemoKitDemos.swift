import DemoKit
import SwiftUI

// DemoKit needs one type per demo. Each type owns its Demo; DemoCatalog.demos is built from this list (#116).
public enum SceneGraphDemos {
    nonisolated static let catalog: [any CatalogDemoView.Type] = [
        KeynoteDemoView.self,
        SceneKitFeaturesDemoView.self,
        ShadowsDemoView.self,
        MaterialsDemoView.self,
        CandyDemoView.self,
        AnimationBlendingDemoView.self,
        DeformationDemoView.self,
        ImportedAssetsDemoView.self,
        PhysicsDemoView.self,
        ParticlesDemoView.self,
        InstancingDemoView.self,
    ]

    public static let all: [any DemoView.Type] = catalog.map { $0 }
}

// The whole demo app as one scene, so apps need not depend on DemoKit themselves.
public struct SceneGraphDemosScene: Scene {
    public init() {
    }

    public var body: some Scene {
        DemoPickerScene(demos: SceneGraphDemos.all)
            .commands {
                DemosCommandMenu()
            }
    }
}

protocol CatalogDemoView: DemoView {
    nonisolated static var demo: Demo { get }
}

extension CatalogDemoView {
    static var metadata: DemoMetadata {
        DemoMetadata(id: .init(demo.id), name: demo.title, systemImage: demo.systemImage, description: demo.summary, group: demo.section.rawValue)
    }

    var body: some View {
        SceneDemoView(demo: Self.demo)
    }
}

struct KeynoteDemoView: CatalogDemoView {
    nonisolated static let demo = Demo(id: "keynote", title: "Introduction to SceneGraph", systemImage: "play.rectangle", section: .basics, summary: "A keynote-style tour built from scene graph features. Arrow keys or click to move between slides; turn on Auto-advance in the inspector.") { KeynoteDemo() }
}

struct SceneKitFeaturesDemoView: CatalogDemoView {
    nonisolated static let demo = Demo(id: "scenekit-features", title: "SceneKit Features", systemImage: "sparkles", section: .basics, summary: "Shapes and text, lights and shadows, actions, constraints, implicit animation, fog, custom shaders and category masks in one scene.") { SceneKitFeaturesDemo() }
}

struct ShadowsDemoView: CatalogDemoView {
    nonisolated static let demo = Demo(id: "shadows", title: "Shadows", systemImage: "shadow", section: .basics, summary: "Directional, spot or point light shadows on their own, with intensity, softness, color, and a floor that can stop receiving them.") { ShadowsDemo() }
}

struct MaterialsDemoView: CatalogDemoView {
    nonisolated static let demo = Demo(id: "pbr-materials", title: "Materials", systemImage: "circle.grid.3x3", section: .materials, summary: "PBR spheres (metallic to the right, roughness upward) beside Blinn-Phong spheres, drawn in one pass.") { PBRMaterialsDemo() }
}

struct CandyDemoView: CatalogDemoView {
    nonisolated static let demo = Demo(id: "candy", title: "Candy", systemImage: "birthday.cake", section: .materials, summary: "Speckled gummies (procedural noise, sheen, diffuse transmission) and iridescent pearl shapes.") { CandyDemo() }
}

struct AnimationBlendingDemoView: CatalogDemoView {
    nonisolated static let demo = Demo(id: "animation-blending", title: "Animation Blending", systemImage: "figure.walk", section: .animation, summary: "Two keyframe clips blended by weight, with an additive clip on top.") { AnimationBlendingDemo() }
}

struct DeformationDemoView: CatalogDemoView {
    nonisolated static let demo = Demo(id: "deformation", title: "Morphs & Skinning", systemImage: "drop", section: .animation, summary: "Blend shapes and a skinned tube, on Blinn-Phong (CPU) and PBR (GPU).") { DeformationDemo() }
}

struct ImportedAssetsDemoView: CatalogDemoView {
    nonisolated static let demo = Demo(id: "imported-assets", title: "Imported Assets", systemImage: "square.and.arrow.down", section: .assets, summary: "An animated glTF fox on an OBJ pedestal, with a scene environment. Click to pick.") { ImportedAssetsDemo() }
}

struct PhysicsDemoView: CatalogDemoView {
    nonisolated static let demo = Demo(id: "physics", title: "Physics", systemImage: "arrow.right.circle", section: .simulation, summary: "Jolt rigid bodies: a crate pyramid and a launched ball. Use Launch and Reset in the toolbar.") { PhysicsDemo() }
}

struct ParticlesDemoView: CatalogDemoView {
    nonisolated static let demo = Demo(id: "particles", title: "Particles", systemImage: "sparkles.rectangle.stack", section: .simulation, summary: "A fountain with gravity and an additive fire, drawn as soft camera-facing sprites.") { ParticlesDemo() }
}

struct InstancingDemoView: CatalogDemoView {
    nonisolated static let demo = Demo(id: "instancing", title: "Instancing", systemImage: "square.grid.3x3.fill", section: .performance, summary: "Thousands of crates drawn with instanced Blinn-Phong calls and frustum culling.") { InstancingDemo() }
}
