import CoreGraphics
import Foundation
import GeometryLite3D
import Metal
import MetalSprockets
@testable import SceneSprockets
@testable import SceneSprocketsBlinnPhong
import Testing

// #512: app content at fixed stages of the frame.
private final class StageLog: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [String] = []

    var entries: [String] {
        lock.withLock { stored }
    }

    func append(_ entry: String) {
        lock.withLock { stored.append(entry) }
    }
}

// Logs when the frame builds it, in draw order.
private struct LoggingElement: Element {
    var log: StageLog
    var name: String

    var body: some Element {
        log.append(name)
        return EmptyElement()
    }
}

@Test(.enabled(if: deviceSupportsMetal4))
@MainActor
func renderStagesDrawInOrder() throws {
    let root = SceneGraph.Node()
    root.addChild(SceneGraph.Node(transform: .init(translation: [0, 0, 5]), content: .camera(Camera(projection: PerspectiveProjection()))))
    let opaque = BlinnPhongSceneMaterial(ambient: .color(0.5), diffuse: .color(0.5), specular: .color(0), shininess: 1)
    let transparent = BlinnPhongSceneMaterial(ambient: .color(0.5), diffuse: .color(0.5), specular: .color(0), shininess: 1, opacity: 0.5)
    root.addChild(SceneGraph.Node(shape: .box(), material: opaque))
    root.addChild(SceneGraph.Node(shape: .sphere(), material: transparent, transform: .init(translation: [0, 0, 1])))
    let sceneGraph = SceneGraph(linearRoot: root)

    let log = StageLog()
    var targets: [RenderStage: RenderStageTargets] = [:]
    var element = SceneGraphElement(sceneGraph: sceneGraph, aspectRatio: 1, renderers: [BlinnPhongMaterialRenderer()])
    for stage in RenderStage.allCases {
        element = element.renderStage(stage) { context, stageTargets in
            #expect(context.cameraMatrix.columns.3.z == 5)
            targets[stage] = stageTargets
            return LoggingElement(log: log, name: "\(stage)").eraseToAnyElement()
        }
    }
    let renderer = try OffscreenRenderer(size: CGSize(width: 32, height: 32))
    _ = try renderer.render(element)
    #expect(log.entries == ["afterOpaque", "beforeTransparent", "afterTransparent", "postProcess"])
    #expect(targets[.postProcess]?.color != nil)
    #expect(targets[.postProcess]?.depth != nil)
}

// With no transparent meshes, the transparent stages still draw, after the opaque meshes.
@Test(.enabled(if: deviceSupportsMetal4))
@MainActor
func renderStagesDrawWithoutTransparentMeshes() throws {
    let root = SceneGraph.Node()
    root.addChild(SceneGraph.Node(transform: .init(translation: [0, 0, 5]), content: .camera(Camera(projection: PerspectiveProjection()))))
    root.addChild(SceneGraph.Node(shape: .box(), material: BlinnPhongSceneMaterial(ambient: .color(0.5), diffuse: .color(0.5), specular: .color(0), shininess: 1)))
    let log = StageLog()
    let element = SceneGraphElement(sceneGraph: SceneGraph(linearRoot: root), aspectRatio: 1, renderers: [BlinnPhongMaterialRenderer()])
        .renderStage(.beforeTransparent) { _, _ in LoggingElement(log: log, name: "beforeTransparent").eraseToAnyElement() }
    _ = try OffscreenRenderer(size: CGSize(width: 32, height: 32)).render(element)
    #expect(log.entries == ["beforeTransparent"])
}
