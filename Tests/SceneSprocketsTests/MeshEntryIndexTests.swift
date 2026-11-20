import GeometryLite3D
import Metal
@testable import SceneSprockets
@testable import SceneSprocketsBlinnPhong
import simd
import SwiftMesh
import Testing

// #337: spatial queries over a graph's mesh entries match testing every entry.
struct MeshEntryIndexTests {
    let device: MTLDevice
    let box: MetalMesh

    init() throws {
        device = try #require(MTLCreateSystemDefaultDevice())
        box = MetalMesh(mesh: .box(), device: device)
    }

    func material() -> BlinnPhongSceneMaterial {
        BlinnPhongSceneMaterial(ambient: .color(0.1), diffuse: .color([1, 1, 1]), specular: .color(0), shininess: 1)
    }

    // A 10 x 10 grid of unit boxes, 2 apart, under a moved parent.
    func grid() -> SceneGraph {
        let root = SceneGraph.Node()
        let parent = root.addChild(SceneGraph.Node(transform: Transform3D(storing: simd_float4x4(translation: [0, 0, -5]))))
        for x in 0 ..< 10 {
            for y in 0 ..< 10 {
                parent.addChild(SceneGraph.Node(label: "\(x),\(y)", transform: Transform3D(storing: simd_float4x4(translation: [Float(x) * 2, Float(y) * 2, 0])), content: .mesh(box, material: material())))
            }
        }
        return SceneGraph(root: root)
    }

    func labels(_ entries: [SceneGraph.MeshEntry]) -> [String] {
        entries.compactMap(\.node.label)
    }

    func bruteForce(_ graph: SceneGraph, _ test: (BoundingBox3D) -> Bool) -> [String] {
        labels(graph.meshEntries().filter { entry in entry.meshBounds.map { test($0.transformed(by: entry.worldTransform)) } ?? true })
    }

    @Test func boxQueryMatchesTestingEveryEntry() {
        let graph = grid()
        let query = BoundingBox3D(min: [3, 3, -6], max: [9, 7, -4])
        let found = labels(graph.meshEntries(overlapping: query))
        #expect(found == bruteForce(graph) { all($0.min .<= query.max) && all($0.max .>= query.min) })
        // Centers at x 4, 6, 8 and y 4, 6.
        #expect(found.count == 6, "\(found)")
    }

    @Test func frustumQueryMatchesTestingEveryEntry() {
        let graph = grid()
        let view = LookAt(position: [0, 0, 10], target: [0, 0, -5], up: [0, 1, 0]).viewMatrix
        let projection = PerspectiveProjection(verticalAngleOfView: .radians(.pi / 8), depthMode: .standard(zClip: 0.1 ... 100)).projectionMatrix(aspectRatio: 1)
        let frustum = Frustum(viewProjection: projection * view)
        let found = labels(graph.meshEntries(in: frustum))
        #expect(found == bruteForce(graph) { frustum.intersects($0) })
        #expect(!found.isEmpty && found.count < 100)
    }

    // The index follows the graph: a moved node is found at its new place.
    @Test func indexFollowsChanges() throws {
        let graph = grid()
        let query = BoundingBox3D(min: [100, 100, -6], max: [102, 102, -4])
        #expect(graph.meshEntries(overlapping: query).isEmpty)
        let node = try #require(graph.root.children.first?.children.first)
        node.transform = Transform3D(storing: simd_float4x4(translation: [101, 101, 0]))
        #expect(labels(graph.meshEntries(overlapping: query)) == ["0,0"])
    }

    @Test func hitTestUsesTheIndex() {
        let graph = grid()
        let hits = graph.hitTest(Ray3D(origin: [4, 6, 10], direction: [0, 0, -1]))
        #expect(hits.first?.node.label == "2,3")
        #expect(hits.allSatisfy { $0.node.label == "2,3" })
    }
}
