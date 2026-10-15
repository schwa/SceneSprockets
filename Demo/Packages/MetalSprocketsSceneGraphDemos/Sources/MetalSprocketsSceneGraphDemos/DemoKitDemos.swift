import DemoKit
import SwiftUI

// DemoKit needs one type per demo; each wraps a DemoCatalog entry in a SceneDemoView.
public enum SceneGraphDemos {
    public static let all: [any DemoView.Type] = [
        SceneKitFeaturesDemoView.self,
        ShadowsDemoView.self,
        MaterialsDemoView.self,
        AnimationBlendingDemoView.self,
        DeformationDemoView.self,
        ImportedAssetsDemoView.self,
        PhysicsDemoView.self,
        InstancingDemoView.self,
    ]
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

extension DemoCatalog {
    static func demo(_ id: String) -> Demo {
        guard let demo = demos.first(where: { $0.id == id }) else {
            preconditionFailure("No demo with id \(id)")
        }
        return demo
    }

    static func metadata(_ id: String) -> DemoMetadata {
        let demo = demo(id)
        return DemoMetadata(id: .init(demo.id), name: demo.title, systemImage: demo.systemImage, description: demo.summary, group: demo.section.rawValue)
    }
}

struct SceneKitFeaturesDemoView: DemoView {
    static let metadata = DemoCatalog.metadata("scenekit-features")
    var body: some View { SceneDemoView(demo: DemoCatalog.demo("scenekit-features")) }
}

struct ShadowsDemoView: DemoView {
    static let metadata = DemoCatalog.metadata("shadows")
    var body: some View { SceneDemoView(demo: DemoCatalog.demo("shadows")) }
}

struct MaterialsDemoView: DemoView {
    static let metadata = DemoCatalog.metadata("pbr-materials")
    var body: some View { SceneDemoView(demo: DemoCatalog.demo("pbr-materials")) }
}

struct AnimationBlendingDemoView: DemoView {
    static let metadata = DemoCatalog.metadata("animation-blending")
    var body: some View { SceneDemoView(demo: DemoCatalog.demo("animation-blending")) }
}

struct DeformationDemoView: DemoView {
    static let metadata = DemoCatalog.metadata("deformation")
    var body: some View { SceneDemoView(demo: DemoCatalog.demo("deformation")) }
}

struct ImportedAssetsDemoView: DemoView {
    static let metadata = DemoCatalog.metadata("imported-assets")
    var body: some View { SceneDemoView(demo: DemoCatalog.demo("imported-assets")) }
}

struct PhysicsDemoView: DemoView {
    static let metadata = DemoCatalog.metadata("physics")
    var body: some View { SceneDemoView(demo: DemoCatalog.demo("physics")) }
}

struct InstancingDemoView: DemoView {
    static let metadata = DemoCatalog.metadata("instancing")
    var body: some View { SceneDemoView(demo: DemoCatalog.demo("instancing")) }
}
