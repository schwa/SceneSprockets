import CoreGraphics
import Foundation
import GeometryLite3D
import Metal
import MetalSprockets
import os
@testable import SceneSprockets
import SceneSprocketsBlinnPhong
import simd
import SwiftMesh
import Testing

// #401: SceneGraphElement reports a GPU interval for each group of passes.
@Test(.enabled(if: deviceSupportsMetal4))
@MainActor
func scenePassesReportGPUTimings() async throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let root = SceneGraph.Node()
    root.addChild(SceneGraph.Node(content: .mesh(MetalMesh(mesh: .box(), device: device), material: BlinnPhongSceneMaterial(color: [0.5, 0.5, 0.5]))))
    root.addChild(SceneGraph.Node(transform: .init(rotation: simd_quatf(angle: -.pi / 3, axis: [1, 0, 0])), content: .light(.directional())))
    let camera = root.addChild(SceneGraph.Node(transform: .init(translation: [0, 0, 4]), content: .camera(Camera(projection: PerspectiveProjection(verticalAngleOfView: .degrees(50))))))
    let sceneGraph = SceneGraph(linearRoot: root)
    sceneGraph.fog = SceneGraph.Fog(color: [1, 1, 1, 1], startDistance: 1, endDistance: 10)

    let labels = OSAllocatedUnfairLock<[String]?>(initialState: nil)
    let renderer = try OffscreenRenderer(size: CGSize(width: 32, height: 32), colorUsage: Shadows.requiredColorUsage, depthUsage: Shadows.requiredDepthUsage)
    let element = SceneGraphElement(sceneGraph: sceneGraph, camera: camera, aspectRatio: 1, renderers: [BlinnPhongMaterialRenderer()], shadows: Shadows())
        .onGPUTimings { timings in labels.withLock { $0 = timings.map(\.label) } }
    _ = try renderer.render(element)
    for _ in 0..<100 where labels.withLock({ $0 }) == nil {
        try await Task.sleep(for: .milliseconds(10))
    }
    let reported = try #require(labels.withLock { $0 })
    #expect(reported.contains(SceneGPUTimingLabel.shadowCasters))
    #expect(reported.contains(SceneGPUTimingLabel.scene))
    #expect(reported.contains(SceneGPUTimingLabel.fog))
}
