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

    // One labeled value in the panel (#599).
    struct Row: Identifiable, Equatable {
        var label: String
        var value: String
        var id: String { label }
    }

    struct Section: Identifiable, Equatable {
        var title: String
        var rows: [Row]
        var id: String { title }
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

    // The frame's numbers and the scene's counts, as the expanded panel shows them. GPU passes appear only when some
    // element is timed.
    func sections(scene statistics: SceneGraph.Statistics) -> [Section] {
        var frame: [Row] = []
        if let timing {
            frame.append(Row(label: "FPS", value: Self.number(timing.currentFPS.rounded())))
            frame.append(Row(label: "Frame", value: Self.milliseconds(timing.deltaTime)))
            frame.append(Row(label: "Average", value: Self.milliseconds(timing.averageDeltaTime)))
            frame.append(Row(label: "Min / max", value: "\(Self.milliseconds(timing.minDeltaTime)) / \(Self.milliseconds(timing.maxDeltaTime))"))
            frame.append(Row(label: "GPU", value: timing.gpuTime.map(Self.milliseconds) ?? "–"))
            frame.append(Row(label: "Frames", value: Self.number(Double(timing.frameCount))))
        }
        var sections: [Section] = []
        if !frame.isEmpty {
            sections.append(Section(title: "Frame", rows: frame))
        }
        sections.append(Section(title: "Scene", rows: [
            Row(label: "Nodes", value: Self.number(Double(statistics.nodeCount))),
            Row(label: "Meshes", value: Self.number(Double(statistics.meshCount))),
            Row(label: "Triangles", value: Self.number(Double(statistics.triangleCount))),
            Row(label: "Vertices", value: Self.number(Double(statistics.vertexCount))),
            Row(label: "Lights", value: Self.number(Double(statistics.lightCount))),
            Row(label: "Cameras", value: Self.number(Double(statistics.cameraCount)))
        ]))
        if let passes = timing?.gpuTimings, !passes.isEmpty {
            sections.append(Section(title: "GPU passes", rows: passes.map { Row(label: $0.label, value: Self.milliseconds($0.duration)) }))
        }
        return sections
    }

    static func milliseconds(_ seconds: TimeInterval) -> String {
        String(format: "%.2f ms", seconds * 1_000)
    }

    static func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0)))
    }
}

struct SceneStatisticsOverlay: View {
    let holder: SceneStatisticsHolder
    let sceneGraph: SceneGraph
    @State private var isExpanded: Bool

    init(holder: SceneStatisticsHolder, sceneGraph: SceneGraph, isExpanded: Bool = false) {
        self.holder = holder
        self.sceneGraph = sceneGraph
        _isExpanded = State(initialValue: isExpanded)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { _ in
            VStack(alignment: .leading, spacing: 8) {
                header
                if isExpanded {
                    Divider()
                    SceneStatisticsSectionsView(sections: holder.sections(scene: sceneGraph.statistics))
                    if !holder.phases.isEmpty {
                        Divider()
                        SceneStatisticsPhaseChart(phases: holder.phases)
                    }
                }
            }
            .font(.caption.monospacedDigit())
            .padding(8)
            .frame(width: isExpanded ? 260 : nil, alignment: .leading)
            .background(.ultraThinMaterial, in: .rect(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.15))
            }
            .environment(\.colorScheme, .dark)
            .contentShape(.rect)
            .onTapGesture { isExpanded.toggle() }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(isExpanded ? "Hides details" : "Shows details")
            .padding()
        }
    }

    // FPS, frame time and the sparkline; always shown.
    private var header: some View {
        let timing = holder.timing
        return HStack(spacing: 8) {
            Text(timing.map { "\(Int($0.currentFPS.rounded())) fps" } ?? "– fps")
                .font(.caption.monospacedDigit().bold())
            Text(timing.map { SceneStatisticsHolder.milliseconds($0.deltaTime) } ?? "–")
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            SceneStatisticsSparkline(values: holder.frameTimes)
                .frame(width: 60, height: 14)
            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
    }
}

private struct SceneStatisticsSectionsView: View {
    let sections: [SceneStatisticsHolder.Section]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(sections) { section in
                VStack(alignment: .leading, spacing: 2) {
                    Text(section.title)
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 1) {
                        ForEach(section.rows) { row in
                            GridRow {
                                Text(row.label)
                                    .foregroundStyle(.secondary)
                                Text(row.value)
                                    .gridColumnAlignment(.trailing)
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                            }
                        }
                    }
                }
            }
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
        .accessibilityHidden(true)
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
            .frame(width: 80, height: 80)
            .overlay {
                // Total on two lines, so it fits inside the ring.
                VStack(spacing: 0) {
                    Text(String(format: "%.1f", phases.reduce(0) { $0 + $1.duration } * 1_000))
                        .font(.caption.monospacedDigit().bold())
                    Text("ms")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                ForEach(phases) { phase in
                    HStack(spacing: 4) {
                        Circle().fill(color(for: phase)).frame(width: 8, height: 8)
                        Text(phase.name)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 4)
                        Text(SceneStatisticsHolder.milliseconds(phase.duration))
                    }
                }
            }
        }
    }
}
