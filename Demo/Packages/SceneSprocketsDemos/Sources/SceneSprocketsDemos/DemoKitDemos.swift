import DemoKit
import SwiftUI

// DemoKit needs one type per demo. Each type owns its Demo; DemoCatalog.demos is built from this list (#116).
public enum SceneGraphDemos {
    // Computed, not stored: arrays of metatypes are not Sendable, so stored globals would not be concurrency-safe.
    nonisolated static var catalog: [any CatalogDemoView.Type] {
        [
            KeynoteDemoView.self,
            SceneKitFeaturesDemoView.self,
            ShadowsDemoView.self,
            DiceDemoView.self,
            GearsDemoView.self,
        ]
    }

    // Catalog demos plus demos with their own SwiftUI layout, which DemoCatalog (single-scene, renderable from the CLI)
    // cannot describe.
    public static var all: [any DemoView.Type] {
        catalog.map { $0 } + [TreeAppreciatorDemoView.self]
    }
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

struct GearsDemoView: CatalogDemoView {
    nonisolated static let demo = Demo(id: "gears", title: "Gears", systemImage: "gearshape.2", section: .basics, summary: "A train of meshing spur gears generated with any number of teeth, in brass, steel and copper.") { GearsDemo() }
}

struct DiceDemoView: CatalogDemoView {
    nonisolated static let demo = Demo(id: "dice", title: "Dice", systemImage: "dice", section: .basics, summary: "Generated D4 to D20 dice in a dozen PBR styles, thrown into a wooden tray with Jolt physics. Click or press Space to roll.") { DiceDemo() }
}

struct TreeAppreciatorDemoView: DemoView {
    static let metadata = DemoMetadata(id: .init("tree-appreciator"), name: "Tree Appreciator", systemImage: "tree", description: "A spot-the-difference game: two procedurally grown trees side by side with a shared camera, seasonal palettes and particles.", group: DemoSection.basics.rawValue)

    var body: some View {
        TreeAppreciatorView()
    }
}

struct ShadowsDemoView: CatalogDemoView {
    nonisolated static let demo = Demo(id: "shadows", title: "Shadows", systemImage: "shadow", section: .basics, summary: "Directional, spot or point light shadows on their own, with intensity, softness, color, and a floor that can stop receiving them.") { ShadowsDemo() }
}
