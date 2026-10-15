public enum DemoCatalog {
    // Demos that need only this package. Apps can append their own (e.g. ones that need extra dependencies).
    public static let demos: [Demo] = [
        Demo(id: "scenekit-features", title: "SceneKit Features", systemImage: "sparkles", section: .basics, summary: "Shapes and text, lights and shadows, actions, constraints, implicit animation, fog, custom shaders and category masks in one scene.") { SceneKitFeaturesDemo() },
        Demo(id: "shadows", title: "Shadows", systemImage: "shadow", section: .basics, summary: "Directional, spot or point light shadows on their own, with intensity, softness, color, and a floor that can stop receiving them.") { ShadowsDemo() },
        Demo(id: "pbr-materials", title: "Materials", systemImage: "circle.grid.3x3", section: .materials, summary: "PBR spheres (metallic to the right, roughness upward) beside Blinn-Phong spheres, drawn in one pass.") { PBRMaterialsDemo() },
        Demo(id: "animation-blending", title: "Animation Blending", systemImage: "figure.walk", section: .animation, summary: "Two keyframe clips blended by weight, with an additive clip on top.") { AnimationBlendingDemo() },
        Demo(id: "deformation", title: "Morphs & Skinning", systemImage: "drop", section: .animation, summary: "Blend shapes and a skinned tube, on Blinn-Phong (CPU) and PBR (GPU).") { DeformationDemo() },
        Demo(id: "imported-assets", title: "Imported Assets", systemImage: "square.and.arrow.down", section: .assets, summary: "An animated glTF fox on an OBJ pedestal, with a scene environment. Click to pick.") { ImportedAssetsDemo() },
        Demo(id: "physics", title: "Physics", systemImage: "arrow.right.circle", section: .simulation, summary: "Jolt rigid bodies: a crate pyramid and a launched ball. Use Launch and Reset in the toolbar.") { PhysicsDemo() },
        Demo(id: "particles", title: "Particles", systemImage: "sparkles.rectangle.stack", section: .simulation, summary: "A fountain with gravity and an additive fire, drawn as soft camera-facing sprites.") { ParticlesDemo() },
        Demo(id: "instancing", title: "Instancing", systemImage: "square.grid.3x3.fill", section: .performance, summary: "Thousands of crates drawn with instanced Blinn-Phong calls and frustum culling.") { InstancingDemo() },
    ]
}
