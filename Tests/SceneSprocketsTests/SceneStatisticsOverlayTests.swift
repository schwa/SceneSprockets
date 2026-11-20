import Foundation
import MetalSprockets
import MetalSprocketsUI
@testable import SceneSprockets
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

@Test
func statisticsCountVerticesOncePerMesh() {
    let mesh = SceneGraph.Shape.box().metalMesh()
    struct PlainMaterial: SceneMaterial {}
    let root = SceneGraph.Node(content: .mesh(mesh, material: PlainMaterial()))
    #expect(SceneGraph(root: root).statistics.vertexCount == mesh.vertexCount)
}
