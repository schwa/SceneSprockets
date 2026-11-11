import Foundation
import GeometryLite3D
@testable import SceneSprockets
import simd
import Testing

// #283: node and scene graph cost per node. Skipped unless SCENESPROCKETS_BENCHMARK=1, so normal test runs stay fast;
// run it alone (other tests running in parallel skew the numbers). Prints `METRIC name=ns_per_node` lines.

private let isEnabled = ProcessInfo.processInfo.environment["SCENESPROCKETS_BENCHMARK"] == "1"

private func measure(_ name: String, count: Int, repeats: Int = 9, _ body: () -> Void) {
    let clock = ContinuousClock()
    body()
    var best = Duration.seconds(1_000)
    for _ in 0..<repeats {
        best = min(best, clock.measure(body))
    }
    let nanoseconds = Double(best.components.seconds) * 1e9 + Double(best.components.attoseconds) / 1e9
    print("METRIC \(name)=\(String(format: "%.2f", nanoseconds / Double(count)))")
}

// 10k groups of 10: a parent with nine children, a mix of content and empty nodes.
private func makeScene(groups: Int) -> (graph: SceneGraph, root: SceneGraph.Node, nodes: [SceneGraph.Node]) {
    let root = SceneGraph.Node()
    var nodes: [SceneGraph.Node] = []
    for group in 0..<groups {
        let parent = root.addChild(SceneGraph.Node(transform: Transform3D(storing: simd_float4x4(translation: [Float(group), 0, 0]))))
        nodes.append(parent)
        for index in 0..<9 {
            let content: SceneGraph.Node.Content = index.isMultiple(of: 3) ? .light(Light(type: .point)) : .empty
            nodes.append(parent.addChild(SceneGraph.Node(transform: Transform3D(storing: simd_float4x4(translation: [0, Float(index), 0])), content: content)))
        }
    }
    return (SceneGraph(root: root), root, nodes)
}

@Test(.enabled(if: isEnabled))
func nodePerformanceBenchmark() {
    let (graph, root, nodes) = makeScene(groups: 10_000)
    let count = nodes.count + 1
    var sink: Float = 0
    var lights = 0

    measure("traversal_ns", count: count) {
        graph.visit { _, transform in sink += transform.columns.3.x }
    }
    measure("flatten_ns", count: count) {
        nodes[nodes.count / 2].transform.translation.z += 1
        lights += graph.lightNodes().count
    }
    measure("read_ns", count: count) {
        for node in nodes {
            sink += node.transform.matrix.columns.3.y
        }
    }
    measure("write_ns", count: count) {
        for node in nodes {
            node.transform.translation.z += 1
        }
    }
    measure("create_attach_ns", count: 20_000, repeats: 3) {
        let (graph, _, _) = makeScene(groups: 2_000)
        _ = graph
    }
    _ = root
    print("BENCHMARK sink \(sink) \(lights)")
}
