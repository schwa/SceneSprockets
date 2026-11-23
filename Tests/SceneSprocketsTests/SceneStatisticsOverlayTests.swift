import Foundation
import MetalSprockets
import MetalSprocketsUI
@testable import SceneSprockets
import SwiftUI
import Testing

// Recording a frame does not invalidate views that read the holder, and the scene is counted at most four times a
// second: the panel redraws on its own 4 Hz timer, not every frame, which made it flicker. It once counted the scene
// in its body, which observed every node.
@Test
@MainActor
func sceneIsCountedAtMostFourTimesASecond() {
    let holder = SceneStatisticsHolder()
    let root = SceneGraph.Node()
    let sceneGraph = SceneGraph(root: root)
    let frame = FrameTimingStatistics(currentFPS: 120, deltaTime: 0.0083, averageDeltaTime: 0.0083, minDeltaTime: 0.008, maxDeltaTime: 0.009, frameCount: 1)
    holder.record(frame, sceneGraph: sceneGraph)
    #expect(holder.sceneStatistics?.nodeCount == 1)
    root.addChild(SceneGraph.Node())
    holder.record(frame, sceneGraph: sceneGraph)
    // Too soon to count again.
    #expect(holder.sceneStatistics?.nodeCount == 1)
}

// Recording a frame does not invalidate views that read the holder: the panel redraws on its own 4 Hz timer, not
// every frame, which made it flicker.
@Test
@MainActor
func recordingAFrameDoesNotRedrawThePanel() {
    let holder = SceneStatisticsHolder()
    final class Flag: @unchecked Sendable {
        var changed = false
    }
    let flag = Flag()
    withObservationTracking {
        _ = holder.timing
        _ = holder.frameTimes
        _ = holder.phases
    } onChange: {
        flag.changed = true
    }
    holder.record(FrameTimingStatistics(currentFPS: 120, deltaTime: 0.0083, averageDeltaTime: 0.0083, minDeltaTime: 0.008, maxDeltaTime: 0.009, frameCount: 1, gpuTime: nil, gpuTimings: [], cpuPhaseTimings: nil))
    #expect(!flag.changed)
    #expect(holder.frameTimes.count == 1)
}

// The sparkline's scale steps between fixed ceilings, so it stays put while frame times move within one.
@Test
@MainActor
func sparklineScaleStepsBetweenCeilings() {
    // 120 fps jitter stays on one scale.
    #expect(SceneStatisticsSparkline.scale(forMaximum: 0.0081) == SceneStatisticsSparkline.scale(forMaximum: 0.0086))
    #expect(SceneStatisticsSparkline.scale(forMaximum: 0.0086) == 1.0 / 60)
    // A 22 ms spike moves it to the 30 fps ceiling, not to 22 ms.
    #expect(SceneStatisticsSparkline.scale(forMaximum: 0.022) == 1.0 / 30)
    // Slower than every ceiling: the maximum itself.
    #expect(SceneStatisticsSparkline.scale(forMaximum: 0.5) == 0.5)
}

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
    struct PlainMaterial: SceneMaterial {}
    let root = SceneGraph.Node()
    root.addChild(SceneGraph.Node(shape: .box(), material: PlainMaterial()))
    let sceneGraph = SceneGraph(root: root)
    for index in 0..<120 {
        holder.record(FrameTimingStatistics(currentFPS: 59.6, deltaTime: 0.0167 + Double(index % 7) * 0.0005, averageDeltaTime: 0.0166, minDeltaTime: 0.016, maxDeltaTime: 0.02, frameCount: 4_242, gpuTime: 0.004, gpuTimings: [GPUTiming(label: "Shadows", startTimestamp: 0, endTimestamp: 0, duration: 0.0015), GPUTiming(label: "Scene", startTimestamp: 0, endTimestamp: 0, duration: 0.0021)], cpuPhaseTimings: cpu), sceneGraph: sceneGraph)
    }
    let renderer = ImageRenderer(content: SceneStatisticsOverlay(holder: holder, isExpanded: true).background(Color(red: 0.2, green: 0.3, blue: 0.45)))
    renderer.scale = 2
    let image = try #require(renderer.cgImage)
    // Taller than the collapsed bar: the sections and the chart are laid out.
    #expect(image.height > 600)
}

// #621: passes with the same label are summed into one row, and the panel stays readable with many of them.
@Test
@MainActor
func repeatedGPUPassesShareOneRow() throws {
    let passes = [("Pre-Pass", 0.0005)] + Array(repeating: ("Simulate", 0.0001), count: 6) + [("Scene", 0.0006)]
    let rows = SceneStatisticsHolder.passRows(passes.map { (label: $0.0, duration: $0.1) })
    #expect(rows.map(\.label) == ["Pre-Pass", "Simulate ×6", "Scene"])
    #expect(rows[1].value == "0.60 ms")

    func expandedHeight(_ timings: [GPUTiming]) throws -> Int {
        let holder = SceneStatisticsHolder()
        holder.record(FrameTimingStatistics(currentFPS: 60, deltaTime: 0.0167, averageDeltaTime: 0.0166, minDeltaTime: 0.016, maxDeltaTime: 0.02, frameCount: 10, gpuTime: 0.004, gpuTimings: timings, cpuPhaseTimings: nil), sceneGraph: SceneGraph(root: SceneGraph.Node()))
        let renderer = ImageRenderer(content: SceneStatisticsOverlay(holder: holder, isExpanded: true))
        return try #require(renderer.cgImage).height
    }
    let distinct = try expandedHeight(rows.map { GPUTiming(label: $0.label, startTimestamp: 0, endTimestamp: 0, duration: 0.0001) })
    let repeated = try expandedHeight(passes.map { GPUTiming(label: $0.0, startTimestamp: 0, endTimestamp: 0, duration: $0.1) })
    // In the app, the repeated labels laid the rows out side by side, a letter per line. ImageRenderer does not show
    // that, so this only checks that repeated passes take no more room than distinct ones.
    #expect(repeated == distinct)
}

// #621: collapsed, the bar is as wide as its contents, not the space it is given.
@Test
@MainActor
func collapsedStatisticsBarFitsItsContents() throws {
    let holder = SceneStatisticsHolder()
    holder.record(FrameTimingStatistics(currentFPS: 60, deltaTime: 0.0167, averageDeltaTime: 0.0166, minDeltaTime: 0.016, maxDeltaTime: 0.02, frameCount: 10, gpuTime: nil, gpuTimings: [], cpuPhaseTimings: nil))
    let renderer = ImageRenderer(content: SceneStatisticsOverlay(holder: holder))
    renderer.proposedSize = ProposedViewSize(width: 1_500, height: nil)
    let image = try #require(renderer.cgImage)
    #expect(image.width < 400, "\(image.width)")
}

@Test
func statisticsCountVerticesOncePerMesh() {
    let mesh = SceneGraph.Shape.box().metalMesh()
    struct PlainMaterial: SceneMaterial {}
    let root = SceneGraph.Node(content: .mesh(mesh, material: PlainMaterial()))
    #expect(SceneGraph(root: root).statistics.vertexCount == mesh.vertexCount)
}
