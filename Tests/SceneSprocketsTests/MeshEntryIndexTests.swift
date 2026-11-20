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

    // #586: the nearest mesh point is on the nearest box's surface.
    @Test func nearestPointFindsTheNearestSurface() throws {
        let graph = grid()
        // In front of box 2,3 (center [4, 6, -5], half size 0.5), 3 units away from its front face.
        let found = try #require(graph.nearestPoint(to: [4, 6, -1.5]))
        #expect(found.node.label == "2,3")
        #expect(abs(found.distance - 3) < 1e-4, "\(found.distance)")
        #expect(simd_distance(found.position, [4, 6, -4.5]) < 1e-4)
        #expect(graph.nearestPoint(to: [4, 6, -1.5], maximumDistance: 2) == nil)
        // Between boxes, the nearest of several.
        let between = try #require(graph.nearestPoint(to: [5.1, 6, -5]))
        #expect(between.node.label == "3,3")
    }

    // #585: posed bounds contain every vertex of the deformed mesh, for skins (two joints) and morph targets.
    @Test func posedBoundsContainTheDeformedMesh() throws {
        let root = SceneGraph.Node()
        let first = root.addChild(SceneGraph.Node(transform: Transform3D(storing: simd_float4x4(translation: [10, 0, 0]))))
        let second = root.addChild(SceneGraph.Node(transform: Transform3D(storing: simd_float4x4(translation: [0, 20, 0]))))
        let skinned = root.addChild(SceneGraph.Node(label: "skinned", content: .mesh(box, material: material())))
        skinned.skin = SceneGraph.Skin(joints: [first, second], inverseBindMatrices: [matrix_identity_float4x4, matrix_identity_float4x4])
        // Vertices alternate between the joints, some blended.
        skinned.skinVertices = (0 ..< box.vertexCount).map { vertex in
            vertex.isMultiple(of: 3) ? SceneGraph.SkinVertex(joints: [0, 1, 0, 0], weights: [0.5, 0.5, 0, 0]) : SceneGraph.SkinVertex(joints: [UInt16(vertex % 2), 0, 0, 0], weights: [1, 0, 0, 0])
        }
        let morphed = root.addChild(SceneGraph.Node(label: "morphed", transform: Transform3D(storing: simd_float4x4(translation: [-30, 0, 0])), content: .mesh(box, material: material())))
        morphed.morphTargets = [
            SceneGraph.MorphTarget(positionDeltas: (0 ..< box.vertexCount).map { [Float($0 % 4), -2, 0] }),
            SceneGraph.MorphTarget(positionDeltas: (0 ..< box.vertexCount).map { [0, 0, Float($0 % 3)] })
        ]
        morphed.morphWeights = [0.75, -1.5]
        let graph = SceneGraph(root: root)
        for entry in graph.meshEntries() {
            let bounds = try #require(entry.posedWorldBounds)
            let deformed = try #require(entry.deformed(revision: graph.revision), "\(entry.node.label ?? "")")
            for position in deformed.mesh.positions() {
                let world = (deformed.modelMatrix * SIMD4(position, 1)).xyz
                #expect(all(world .>= bounds.min - 1e-4) && all(world .<= bounds.max + 1e-4), "\(entry.node.label ?? ""): \(world) outside \(bounds)")
            }
        }
        // The skinned mesh is found where its joints put it (a box spanning both joints, x -0.5...10.5, y -0.5...20.5),
        // and nothing is found outside every posed box.
        #expect(labels(graph.meshEntries(overlapping: BoundingBox3D(min: [9, -1, -1], max: [11, 1, 1]))) == ["skinned"])
        #expect(graph.meshEntries(overlapping: BoundingBox3D(min: [15, 15, -1], max: [17, 17, 1])).isEmpty)
    }

    // #588: after a transform-only change, entries carry the new world transform, opacity, morph weights and skin pose,
    // the same as entries built from scratch.
    @Test func transformOnlyChangesUpdateEntries() throws {
        let root = SceneGraph.Node()
        let joint = root.addChild(SceneGraph.Node())
        let parent = root.addChild(SceneGraph.Node())
        let morphed = parent.addChild(SceneGraph.Node(label: "morphed", content: .mesh(box, material: material())))
        morphed.morphTargets = [SceneGraph.MorphTarget(positionDeltas: Array(repeating: [1, 0, 0], count: box.vertexCount))]
        morphed.morphWeights = [0]
        let skinned = root.addChild(SceneGraph.Node(label: "skinned", content: .mesh(box, material: material())))
        skinned.skin = SceneGraph.Skin(joints: [joint], inverseBindMatrices: [matrix_identity_float4x4])
        skinned.skinVertices = Array(repeating: SceneGraph.SkinVertex(joints: [0, 0, 0, 0], weights: [1, 0, 0, 0]), count: box.vertexCount)
        let graph = SceneGraph(root: root)
        let before = graph.meshEntries()
        #expect(before.count == 2)
        let structure = graph.revision.structure

        parent.transform = Transform3D(storing: simd_float4x4(translation: [5, 0, 0]))
        parent.opacity = 0.5
        morphed.morphWeights = [0.25]
        joint.transform = Transform3D(storing: simd_float4x4(translation: [0, 7, 0]))
        #expect(graph.revision.structure == structure, "Only transform-revision fields changed")
        let after = graph.meshEntries()
        #expect(after.map(\.nodeID) == before.map(\.nodeID))
        let morphedEntry = try #require(after.first { $0.node.label == "morphed" })
        #expect(morphedEntry.worldTransform.columns.3.x == 5 && morphedEntry.opacity == 0.5 && morphedEntry.morphWeights == [0.25])
        #expect(after.first { $0.node.label == "skinned" }?.skin?.jointWorldTransforms.first?.columns.3.y == 7)

        // A structural change rebuilds the entries.
        skinned.removeFromParent()
        #expect(graph.meshEntries().map(\.node.label) == ["morphed"])
    }

    @Test func hitTestUsesTheIndex() {
        let graph = grid()
        let hits = graph.hitTest(Ray3D(origin: [4, 6, 10], direction: [0, 0, -1]))
        #expect(hits.first?.node.label == "2,3")
        #expect(hits.allSatisfy { $0.node.label == "2,3" })
    }
}
