import GeometryLite3D
import Metal
@testable import SceneSprockets
@testable import SceneSprocketsBlinnPhong
import simd
import SwiftMesh
import Testing

private var material: BlinnPhongSceneMaterial {
    BlinnPhongSceneMaterial(ambient: .color([1, 1, 1]), diffuse: .color([1, 1, 1]), specular: .color([1, 1, 1]), shininess: 1)
}

private func translation(_ x: Float, _ y: Float, _ z: Float) -> simd_float4x4 {
    simd_float4x4(columns: ([1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0], [x, y, z, 1]))
}

@Test
func undeformedMeshIsUnchanged() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let node = SceneGraph.Node(content: .mesh(MetalMesh(mesh: .box(), device: device), material: material))
    let sceneGraph = SceneGraph(root: node)
    #expect(sceneGraph.meshEntries()[0].deformed(revision: sceneGraph.revision) == nil)
}

@Test
func morphTargetsAreBlendedOnCPU() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    for layout in [MetalMesh.BufferLayout.interleaved, .separateBuffers] {
        let box = MetalMesh(mesh: .box(), device: device, bufferLayout: layout)
        let node = SceneGraph.Node(content: .mesh(box, material: material))
        node.morphTargets = [SceneGraph.MorphTarget(positionDeltas: Array(repeating: [0, 1, 0], count: box.vertexCount))]
        node.morphWeights = [0.5]
        let sceneGraph = SceneGraph(root: node)

        let deformed = try #require(sceneGraph.meshEntries()[0].deformed(revision: sceneGraph.revision))
        #expect(deformed.mesh.positionBounds()?.min.y == 0)
        #expect(deformed.mesh.positionBounds()?.max.y == 1)
        #expect(deformed.modelMatrix == translation(0, 0, 0))
        // The source mesh is untouched.
        #expect(box.positionBounds()?.max.y == 0.5)
    }
}

@Test
func skinnedMeshFollowsJointsAndIgnoresNodeTransform() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let box = MetalMesh(mesh: .box(), device: device)
    let root = SceneGraph.Node()
    let joint = root.addChild(SceneGraph.Node(transform: translation(0, 5, 0)))
    let skinned = root.addChild(SceneGraph.Node(transform: translation(100, 0, 0), content: .mesh(box, material: material)))
    skinned.skin = SceneGraph.Skin(joints: [joint], inverseBindMatrices: [matrix_identity_float4x4])
    skinned.skinVertices = Array(repeating: SceneGraph.SkinVertex(joints: [0, 0, 0, 0], weights: [1, 0, 0, 0]), count: box.vertexCount)
    let sceneGraph = SceneGraph(root: root)

    var deformed = try #require(sceneGraph.meshEntries()[0].deformed(revision: sceneGraph.revision))
    #expect(deformed.mesh.positionBounds()?.min.y == 4.5)
    #expect(deformed.modelMatrix == matrix_identity_float4x4)

    // Moving the joint re-deforms; an unchanged graph reuses the cached mesh.
    let cachedBuffer = deformed.mesh.vertexBuffer
    #expect(sceneGraph.meshEntries()[0].deformed(revision: sceneGraph.revision)?.mesh.vertexBuffer === cachedBuffer)
    joint.trs.translation = [0, 7, 0]
    deformed = try #require(sceneGraph.meshEntries()[0].deformed(revision: sceneGraph.revision))
    #expect(deformed.mesh.positionBounds()?.min.y == 6.5)
}
