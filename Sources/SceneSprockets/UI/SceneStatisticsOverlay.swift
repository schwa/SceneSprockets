import Charts
import MetalSprockets
import MetalSprocketsUI
import SwiftUI

// The data behind the statistics overlay (#131), like SCNView.showsStatistics: FPS, a frame-time history for the
// sparkline, and the previous frame's time per phase for the donut chart.
@MainActor
@Observable
final class SceneStatisticsHolder {
    struct Phase: Identifiable, Equatable {
        var name: String
        var duration: TimeInterval
        var id: String { name }
    }

    static let historyLength = 120

    private(set) var timing: FrameTimingStatistics?
    private(set) var frameTimes: [TimeInterval] = []

    func record(_ statistics: FrameTimingStatistics) {
        timing = statistics
        frameTimes.append(statistics.deltaTime)
        if frameTimes.count > Self.historyLength {
            frameTimes.removeFirst(frameTimes.count - Self.historyLength)
        }
    }

    var phases: [Phase] {
        guard let timing else {
            return []
        }
        var phases: [Phase] = []
        if let cpu = timing.cpuPhaseTimings {
            if let content = cpu.content {
                phases.append(Phase(name: "Scene update", duration: content))
            }
            phases.append(Phase(name: "Element update", duration: cpu.update))
            phases.append(Phase(name: "Setup", duration: cpu.setup))
            phases.append(Phase(name: "Encoding", duration: cpu.workload))
        }
        if let gpu = timing.gpuTime {
            phases.append(Phase(name: "GPU", duration: gpu))
        }
        return phases
    }
}

struct SceneStatisticsOverlay: View {
    let holder: SceneStatisticsHolder
    let sceneGraph: SceneGraph
    @State private var isExpanded = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { _ in
            VStack(alignment: .leading, spacing: 6) {
                if isExpanded {
                    SceneStatisticsPhaseChart(phases: holder.phases)
                }
                bar
            }
            .font(.caption.monospacedDigit())
            // A tight badge inset; the default padding is too large for caption text.
            .padding(4)
            .background(.black.opacity(0.6), in: .rect(cornerRadius: 4))
            .foregroundStyle(.white)
            .contentShape(.rect)
            .onTapGesture { isExpanded.toggle() }
            .accessibilityAddTraits(.isButton)
            .padding()
        }
    }

    private var bar: some View {
        let statistics = sceneGraph.statistics
        let fps = holder.timing.map { "\(Int($0.currentFPS.rounded()))fps" } ?? "–"
        return HStack(spacing: 8) {
            Text("Metal \(fps) \u{00B7} \(statistics.meshCount) meshes \u{00B7} \(statistics.triangleCount) triangles \u{00B7} \(statistics.vertexCount) vertices \u{00B7} \(statistics.lightCount) lights")
            SceneStatisticsSparkline(values: holder.frameTimes)
                .frame(width: 60, height: 14)
        }
    }
}

private struct SceneStatisticsSparkline: View {
    let values: [TimeInterval]

    var body: some View {
        Canvas { context, size in
            guard values.count > 1, let maximum = values.max(), maximum > 0 else {
                return
            }
            var path = Path()
            for (index, value) in values.enumerated() {
                let point = CGPoint(x: size.width * CGFloat(index) / CGFloat(SceneStatisticsHolder.historyLength - 1), y: size.height * (1 - CGFloat(value / maximum)))
                if index == 0 {
                    path.move(to: point)
                } else {
                    path.addLine(to: point)
                }
            }
            context.stroke(path, with: .color(.green), lineWidth: 1)
        }
    }
}

private struct SceneStatisticsPhaseChart: View {
    let phases: [SceneStatisticsHolder.Phase]

    private static let colors: [Color] = [.purple, .blue, .teal, .orange, .red, .yellow]

    private func color(for phase: SceneStatisticsHolder.Phase) -> Color {
        let index = phases.firstIndex(of: phase) ?? 0
        return Self.colors[index % Self.colors.count]
    }

    var body: some View {
        HStack(spacing: 8) {
            Chart(phases) { phase in
                SectorMark(angle: .value("Time", phase.duration), innerRadius: .ratio(0.55))
                    .foregroundStyle(color(for: phase))
            }
            .chartBackground { _ in
                Text(String(format: "%.1f ms", phases.reduce(0) { $0 + $1.duration } * 1_000))
            }
            .frame(width: 90, height: 90)
            VStack(alignment: .leading, spacing: 2) {
                ForEach(phases) { phase in
                    HStack(spacing: 4) {
                        Circle().fill(color(for: phase)).frame(width: 8, height: 8)
                        Text("\(phase.name) \(String(format: "%.2f ms", phase.duration * 1_000))")
                    }
                }
            }
        }
    }
}
