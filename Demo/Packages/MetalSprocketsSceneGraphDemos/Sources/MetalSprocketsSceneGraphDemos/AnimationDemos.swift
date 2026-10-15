import MetalSprocketsAddOns
import MetalSprocketsAddOnsShaders
import MetalSprocketsSceneGraph
import MetalSprocketsSceneGraphPBR
import MetalSprocketsSceneGraphRenderer
import SwiftMesh
import simd

private typealias Clip = SceneGraph.AnimationClip

// Two keyframe clips blended by a slider, with an additive breathing clip on top.
final class AnimationBlendingDemo: DemoScene {
    private let mixer: SceneGraph.AnimationMixer
    private var controller: SceneGraph.AnimationController

    init() {
        let box = MetalMesh(mesh: .box(), device: demoDevice)
        let sphere = MetalMesh(mesh: .sphere(), device: demoDevice)
        let root = SceneGraph.Node(label: "Root")
        root.addChild(.camera(eye: [0, 2.5, 8], target: [0, 1.2, 0]))
        root.addChild(.pointLight("Key Light", at: [3, 5, 5], intensity: 50))
        _ = SceneGraph.Node(parent: root, label: "Floor", transform: .translation(0, -0.05, 0) * .scale(10, 0.1, 10), content: .mesh(box, material: BlinnPhongMaterial.plastic([0.6, 0.6, 0.65], shininess: 8)))
        let body = SceneGraph.Node(parent: root, label: "Body", trs: .init(translation: [0, 1, 0]), content: .mesh(box, material: BlinnPhongMaterial.plastic([0.9, 0.5, 0.2])))
        let head = SceneGraph.Node(parent: body, label: "Head", trs: .init(translation: [0, 0.95, 0], scale: [0.7, 0.7, 0.7]), content: .mesh(sphere, material: BlinnPhongMaterial.plastic([0.95, 0.85, 0.7])))

        func vector(_ values: [SIMD3<Float>]) -> [Float] { values.flatMap { [$0.x, $0.y, $0.z] } }
        func quaternions(_ angles: [Float], axis: SIMD3<Float>) -> [Float] {
            angles.flatMap { angle -> [Float] in
                let vector = simd_quatf(angle: angle, axis: axis).vector
                return [vector.x, vector.y, vector.z, vector.w]
            }
        }
        let bounce = Clip(name: "Bounce", channels: [
            .init(target: body, path: .translation, sampler: .init(times: [0, 0.5, 1], values: vector([[0, 1, 0], [0, 2.2, 0], [0, 1, 0]]), interpolation: .linear)),
        ])
        let sway = Clip(name: "Sway", channels: [
            .init(target: body, path: .rotation, sampler: .init(times: [0, 1, 2], values: quaternions([-0.4, 0.4, -0.4], axis: [0, 0, 1]), interpolation: .linear)),
            .init(target: head, path: .rotation, sampler: .init(times: [0, 1, 2], values: quaternions([0.6, -0.6, 0.6], axis: [0, 1, 0]), interpolation: .linear)),
        ])
        let breathe = Clip(name: "Breathe", channels: [
            .init(target: head, path: .scale, sampler: .init(times: [0, 0.75, 1.5], values: vector([[0.7, 0.7, 0.7], [0.85, 0.85, 0.85], [0.7, 0.7, 0.7]]), interpolation: .linear)),
        ])
        let clips = [bounce, sway, breathe]
        mixer = SceneGraph.AnimationMixer(clips: clips)
        controller = SceneGraph.AnimationController(clips: clips)
        super.init(sceneGraph: SceneGraph(root: root), cameraMatrix: .camera(eye: [0, 2.5, 8], target: [0, 1.2, 0]), parameters: [
            .slider("Bounce ↔ Sway", 0...1, default: 0.5),
            .toggle("Breathe (additive)", default: true),
            .slider("Speed", 0...2, default: 1),
        ])
    }

    override func update(time: Float, deltaTime: Float) {
        controller.blend([0, 1], parameter: self[value: "Bounce ↔ Sway"], speed: self[value: "Speed"])
        controller.setAdditive(2, weight: self[flag: "Breathe (additive)"] ? 1 : 0)
        controller.advance(by: deltaTime)
        mixer.apply(controller.layers)
    }
}

// Morph targets and skinning, each drawn by Blinn-Phong (CPU deformation, left) and PBR (GPU deformation, right):
// blend-shape blobs on top, tubes bent by a three-joint skeleton below.
final class DeformationDemo: DemoScene {
    private let morphed: [SceneGraph.Node]
    private var bendingJoints: [SceneGraph.Node] = []

    init() {
        let mesh = MetalMesh(mesh: .icoSphere(subdivisions: 4), device: demoDevice)
        let positions = mesh.float3Attribute(.position)
        let normals = mesh.float3Attribute(.normal)
        // Six smooth bumps, one along each axis. Displace along the direction from the center, not the vertex normal:
        // each face has its own vertices and normals, so moving along normals tears the faces apart.
        let axes: [SIMD3<Float>] = [[1, 0, 0], [-1, 0, 0], [0, 1, 0], [0, -1, 0], [0, 0, 1], [0, 0, -1]]
        let bumpDeltas = positions.map { position in
            let direction = simd_normalize(position)
            return direction * (axes.map { pow(max(0, simd_dot(direction, $0)), 12) }.max() ?? 0) * 0.6
        }
        let squashDeltas = positions.map { SIMD3<Float>($0.x * 0.5, -$0.y * 0.5, $0.z * 0.5) }
        let indices = mesh.submeshes.flatMap(\.indices)
        // Normal deltas too, so the lighting follows the new shape.
        let bumps = SceneGraph.MorphTarget(positionDeltas: bumpDeltas, normalDeltas: Self.normalDeltas(positions: positions, normals: normals, deltas: bumpDeltas, indices: indices))
        let squash = SceneGraph.MorphTarget(positionDeltas: squashDeltas, normalDeltas: Self.normalDeltas(positions: positions, normals: normals, deltas: squashDeltas, indices: indices))

        let root = SceneGraph.Node(label: "Root")
        root.addChild(.camera(eye: [0, 2.5, 10], target: [0, 2, 0]))
        root.addChild(.pointLight("Key Light", at: [2, 6, 5], intensity: 50))
        root.addChild(.pointLight("Fill Light", at: [-3, 1, 3], color: [0.5, 0.6, 1], intensity: 15))
        let left = SceneGraph.Node(parent: root, label: "Blinn-Phong Blob", trs: .init(translation: [-1.5, 4.3, 0]), content: .mesh(mesh, material: BlinnPhongMaterial.plastic([0.3, 0.8, 0.5], shininess: 48)))
        let right = SceneGraph.Node(parent: root, label: "PBR Blob", trs: .init(translation: [1.5, 4.3, 0]), content: .mesh(mesh, material: try! PBRSceneMaterial(device: demoDevice, baseColor: [0.3, 0.8, 0.5, 1], metallic: 0.1, roughness: 0.3)))
        morphed = [left, right]
        for node in morphed {
            node.morphTargets = [bumps, squash]
            node.morphWeights = [0, 0]
        }

        let tube = MetalMesh(mesh: Self.tube(height: 3, radius: 0.3, rings: 24, segments: 24), device: demoDevice)
        let skinVertices = tube.float3Attribute(.position).map { position in
            // Linear falloff between joints at y = 0, 1 and 2.
            let y = min(max(position.y, 0), 2)
            let lower = min(Int(y), 1)
            let fraction = y - Float(lower)
            return SceneGraph.SkinVertex(joints: [UInt16(lower), UInt16(lower + 1), 0, 0], weights: [1 - fraction, fraction, 0, 0])
        }
        let box = MetalMesh(mesh: .box(), device: demoDevice)
        _ = SceneGraph.Node(parent: root, label: "Floor", transform: .translation(0, -0.05, 0) * .scale(10, 0.1, 6), content: .mesh(box, material: BlinnPhongMaterial.plastic([0.6, 0.6, 0.6], shininess: 8)))
        let tubeMaterials: [(String, Float, any MetalSprocketsSceneGraph.Material)] = [
            ("Blinn-Phong", -1.5, BlinnPhongMaterial.plastic([0.9, 0.6, 0.2])),
            ("PBR", 1.5, try! PBRSceneMaterial(device: demoDevice, baseColor: [0.9, 0.6, 0.2, 1], metallic: 0, roughness: 0.4)),
        ]
        for (name, x, material) in tubeMaterials {
            let skeleton = SceneGraph.Node(parent: root, label: "\(name) Skeleton", trs: .init(translation: [x, 0, 0]))
            let joint0 = SceneGraph.Node(parent: skeleton, label: "\(name) Joint 0")
            let joint1 = SceneGraph.Node(parent: joint0, label: "\(name) Joint 1", trs: .init(translation: [0, 1, 0]))
            let joint2 = SceneGraph.Node(parent: joint1, label: "\(name) Joint 2", trs: .init(translation: [0, 1, 0]))
            bendingJoints += [joint1, joint2]
            // The tube is modelled at the origin, in the skeleton's space: inverse bind matrices undo each joint's rest
            // transform relative to the skeleton, so at rest the tube sits on its skeleton.
            let skeletonInverse = skeleton.worldTransform.inverse
            let inverseBind = [joint0, joint1, joint2].map { (skeletonInverse * $0.worldTransform).inverse }
            let skinned = SceneGraph.Node(parent: root, label: "\(name) Tube", content: .mesh(tube, material: material))
            skinned.skin = SceneGraph.Skin(joints: [joint0, joint1, joint2], inverseBindMatrices: inverseBind)
            skinned.skinVertices = skinVertices
        }
        super.init(
            sceneGraph: SceneGraph(root: root),
            renderers: [BlinnPhongMaterialRenderer(), PBRMaterialRenderer(device: demoDevice)],
            cameraMatrix: .camera(eye: [0, 2.5, 10], target: [0, 2, 0]),
            parameters: [.toggle("Animate", default: true), .slider("Bumps", 0...1, default: 0), .slider("Squash", 0...1, default: 0), .slider("Bend", -0.8...0.8, default: 0.5)]
        )
    }

    override func update(time: Float, deltaTime: Float) {
        if self[flag: "Animate"] {
            self[value: "Bumps"] = (sin(time * 1.3) + 1) / 2
            self[value: "Squash"] = max(0, sin(time * 0.7))
        }
        let weights = [self[value: "Bumps"], self[value: "Squash"]]
        for node in morphed where node.morphWeights != weights {
            node.morphWeights = weights
        }
        if self[flag: "Animate"] {
            self[value: "Bend"] = sin(time * 1.5) * 0.7
        }
        let rotation = simd_quatf(angle: self[value: "Bend"], axis: [0, 0, 1])
        for joint in bendingJoints where joint.trs.rotation != rotation {
            joint.trs.rotation = rotation
        }
    }
}

extension DeformationDemo {
    // Smooth normals of the fully morphed shape minus the rest normals. Vertices at the same position (UV seams) share
    // a normal, so seams do not show.
    static func normalDeltas(positions: [SIMD3<Float>], normals: [SIMD3<Float>], deltas: [SIMD3<Float>], indices: [UInt32]) -> [SIMD3<Float>] {
        let morphed = zip(positions, deltas).map { $0 + $1 }
        let keys = positions.map { SIMD3<Int32>(($0 * 10_000).rounded(.toNearestOrEven)) }
        var sums: [SIMD3<Int32>: SIMD3<Float>] = [:]
        for triangle in stride(from: 0, to: indices.count - 2, by: 3) {
            let a = Int(indices[triangle]), b = Int(indices[triangle + 1]), c = Int(indices[triangle + 2])
            let faceNormal = simd_cross(morphed[b] - morphed[a], morphed[c] - morphed[a])
            for vertex in [a, b, c] {
                sums[keys[vertex], default: .zero] += faceNormal
            }
        }
        return positions.indices.map { index in
            let sum = sums[keys[index]] ?? normals[index]
            let normal = simd_length(sum) > 0 ? simd_normalize(sum) : normals[index]
            // Keep the rest orientation's facing (meshes may wind either way).
            let oriented = simd_dot(normal, normals[index]) < 0 ? -normal : normal
            return oriented - normals[index]
        }
    }

    // An open tube along +Y from 0 to `height`, with enough rings to bend smoothly.
    static func tube(height: Float, radius: Float, rings: Int, segments: Int) -> Mesh {
        var positions: [SIMD3<Float>] = []
        for ring in 0...rings {
            let y = height * Float(ring) / Float(rings)
            for segment in 0..<segments {
                let angle = Float(segment) / Float(segments) * 2 * .pi
                positions.append([radius * cos(angle), y, radius * sin(angle)])
            }
        }
        var faces: [[Int]] = []
        for ring in 0..<rings {
            for segment in 0..<segments {
                let next = (segment + 1) % segments
                let a = ring * segments + segment
                let b = (ring + 1) * segments + segment
                let c = (ring + 1) * segments + next
                let d = ring * segments + next
                faces.append([a, b, c, d])
            }
        }
        var mesh = Mesh(positions: positions, faces: faces).withSmoothNormals()
        // Blinn-Phong needs texture coordinates: u around the tube, v along it (from each corner's start vertex).
        mesh.textureCoordinates = mesh.topology.halfEdges.map { halfEdge in
            let vertex = halfEdge.origin.raw
            return [Float(vertex % segments) / Float(segments), Float(vertex / segments) / Float(rings)]
        }
        return mesh
    }
}
