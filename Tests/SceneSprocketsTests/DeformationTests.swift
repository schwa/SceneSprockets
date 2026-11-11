import CoreGraphics
import GeometryLite3D
import Metal
import MetalSprockets
import MetalSupport
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

// #298: Blinn-Phong meshes are morphed and skinned by a GPU pre-pass, with the same result as the CPU path.
@Test(.enabled(if: deviceSupportsMetal4), arguments: [MetalMesh.BufferLayout.interleaved, .separateBuffers])
@MainActor
func gpuDeformationMatchesCPU(layout: MetalMesh.BufferLayout) throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let box = MetalMesh(mesh: .box(), device: device, bufferLayout: layout)
    let root = SceneGraph.Node()
    root.addChild(SceneGraph.Node(transform: translation(0, 0, 10), content: .camera(Camera(projection: PerspectiveProjection(verticalAngleOfView: .degrees(60))))))
    let joint = root.addChild(SceneGraph.Node(trs: Transform3D(translation: [0, 0.5, 0], rotation: simd_quatf(angle: 0.4, axis: [0, 0, 1]))))
    let node = root.addChild(SceneGraph.Node(transform: translation(100, 0, 0), content: .mesh(box, material: material)))
    node.morphTargets = [
        SceneGraph.MorphTarget(positionDeltas: (0..<box.vertexCount).map { [0, Float($0 % 3) * 0.1, 0] }, normalDeltas: Array(repeating: [0.2, 0, 0], count: box.vertexCount)),
        SceneGraph.MorphTarget(positionDeltas: Array(repeating: [0.3, 0, 0], count: box.vertexCount))
    ]
    node.morphWeights = [0.5, 1]
    node.skin = SceneGraph.Skin(joints: [root, joint], inverseBindMatrices: [matrix_identity_float4x4, matrix_identity_float4x4])
    node.skinVertices = (0..<box.vertexCount).map { SceneGraph.SkinVertex(joints: [0, 1, 0, 0], weights: $0.isMultiple(of: 2) ? [1, 0, 0, 0] : [0.25, 0.75, 0, 0]) }
    let sceneGraph = SceneGraph(root: root)

    let renderer = try OffscreenRenderer(size: CGSize(width: 32, height: 32))
    _ = try renderer.render(SceneGraphElement(sceneGraph: sceneGraph, aspectRatio: 1, renderers: [BlinnPhongMaterialRenderer()]))
    // The renderer used the GPU result, not the CPU path.
    #expect(node.deformationCache == nil)
    let gpu = try #require(node.gpuDeformation?.current)
    #expect(gpu.revision == sceneGraph.revision)
    #expect(gpu.modelMatrix == matrix_identity_float4x4)

    let cpu = try #require(sceneGraph.meshEntries()[0].deformed(revision: sceneGraph.revision))
    for semantic in [VertexDescriptor.Attribute.Semantic.position, .normal] {
        let gpuValues = try #require(gpu.mesh.float3Values(semantic))
        let cpuValues = try #require(cpu.mesh.float3Values(semantic))
        #expect(gpuValues.count == box.vertexCount)
        #expect(zip(gpuValues, cpuValues).allSatisfy { simd_distance($0, $1) < 1e-4 }, "\(semantic)")
    }
    #expect(box.positionBounds()?.max.y == 0.5)
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
