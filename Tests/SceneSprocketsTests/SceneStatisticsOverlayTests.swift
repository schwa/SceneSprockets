import Foundation
import MetalSprockets
import MetalSprocketsUI
@testable import SceneSprockets
import SwiftUI
import Testing

// #131: the statistics overlay keeps a bounded frame-time history and splits frame time by phase.
@Test
@MainActor
func statisticsHolderKeepsBoundedHistoryAndPhases() {
    let holder = SceneStatisticsHolder()
    #expect(holder.phases.isEmpty)
    for index in 0..<(SceneStatisticsHolder.historyLength + 10) {
        holder.record(FrameTimingStatistics(currentFPS: 60, deltaTime: TimeInterval(index), averageDeltaTime: 0, minDeltaTime: 0, maxDeltaTime: 0, frameCount: index))
    }
    #expect(holder.frameTimes.count == SceneStatisticsHolder.historyLength)
    #expect(holder.frameTimes.last == TimeInterval(SceneStatisticsHolder.historyLength + 9))

    let cpu = CPUPhaseTimings(content: 0.001, update: 0.002, setup: 0.003, workload: 0.004)
    holder.record(FrameTimingStatistics(currentFPS: 60, deltaTime: 0.016, averageDeltaTime: 0, minDeltaTime: 0, maxDeltaTime: 0, frameCount: 1, gpuTime: 0.005, cpuPhaseTimings: cpu))
    #expect(holder.phases.map(\.duration) == [0.001, 0.002, 0.003, 0.004, 0.005])
}

// #599: the expanded panel lists frame timing, scene counts and timed GPU passes.
@Test
@MainActor
func statisticsPanelSections() {
    let holder = SceneStatisticsHolder()
    let scene = SceneGraph.Statistics(nodeCount: 3, meshCount: 2, triangleCount: 1_200, vertexCount: 800, lightCount: 1, cameraCount: 1)
    #expect(holder.sections(scene: scene).map(\.title) == ["Scene"])

    let pass = GPUTiming(label: "Shadows", startTimestamp: 0, endTimestamp: 0, duration: 0.0015)
    holder.record(FrameTimingStatistics(currentFPS: 59.6, deltaTime: 0.0167, averageDeltaTime: 0.0166, minDeltaTime: 0.016, maxDeltaTime: 0.02, frameCount: 42, gpuTime: 0.004, gpuTimings: [pass]))
    let sections = holder.sections(scene: scene)
    #expect(sections.map(\.title) == ["Frame", "Scene", "GPU passes"])
    let frame = Dictionary(uniqueKeysWithValues: sections[0].rows.map { ($0.label, $0.value) })
    #expect(frame["FPS"] == "60")
    #expect(frame["Frame"] == "16.70 ms")
    #expect(frame["GPU"] == "4.00 ms")
    #expect(sections[1].rows.first { $0.label == "Triangles" }?.value == 1_200.0.formatted(.number.precision(.fractionLength(0))))
    #expect(sections[2].rows == [.init(label: "Shadows", value: "1.50 ms")])
}

// #599: the expanded panel lays out with every section.
@Test
@MainActor
func expandedStatisticsPanelRenders() throws {
    let holder = SceneStatisticsHolder()
    let cpu = CPUPhaseTimings(content: 0.001, update: 0.002, setup: 0.0005, workload: 0.003)
    for index in 0..<120 {
        holder.record(FrameTimingStatistics(currentFPS: 59.6, deltaTime: 0.0167 + Double(index % 7) * 0.0005, averageDeltaTime: 0.0166, minDeltaTime: 0.016, maxDeltaTime: 0.02, frameCount: 4_242, gpuTime: 0.004, gpuTimings: [GPUTiming(label: "Shadows", startTimestamp: 0, endTimestamp: 0, duration: 0.0015), GPUTiming(label: "Scene", startTimestamp: 0, endTimestamp: 0, duration: 0.0021)], cpuPhaseTimings: cpu))
    }
    struct PlainMaterial: SceneMaterial {}
    let root = SceneGraph.Node()
    root.addChild(SceneGraph.Node(shape: .box(), material: PlainMaterial()))
    let renderer = ImageRenderer(content: SceneStatisticsOverlay(holder: holder, sceneGraph: SceneGraph(root: root), isExpanded: true).background(Color(red: 0.2, green: 0.3, blue: 0.45)))
    renderer.scale = 2
    let image = try #require(renderer.cgImage)
    // Taller than the collapsed bar: the sections and the chart are laid out.
    #expect(image.height > 600)
}

@Test
func statisticsCountVerticesOncePerMesh() {
    let mesh = SceneGraph.Shape.box().metalMesh()
    struct PlainMaterial: SceneMaterial {}
    let root = SceneGraph.Node(content: .mesh(mesh, material: PlainMaterial()))
    #expect(SceneGraph(root: root).statistics.vertexCount == mesh.vertexCount)
}
