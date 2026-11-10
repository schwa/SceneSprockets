import GeometryLite3D
import Metal
import SceneSprockets
import SceneSprocketsBlinnPhong
import simd
import SwiftUI

struct ContentView: View {
    @State private var sceneGraph = Self.makeSceneGraph()
    @State private var shadows = SceneGraphShadows(intensity: 0.7, softness: 2)

    var body: some View {
        SceneView(sceneGraph: sceneGraph, options: [.allowsCameraControl], renderers: [BlinnPhongMaterialRenderer()], shadows: shadows)
    }

    private static func material(_ color: SIMD3<Float>, shininess: Float = 32, opacity: Float = 1, emission: SIMD3<Float> = .zero) -> BlinnPhongSceneMaterial {
        BlinnPhongSceneMaterial(ambient: .color(color * 0.3), diffuse: .color(color), specular: .color(0.5), shininess: shininess, opacity: opacity, emission: .color(emission))
    }

    private static func makeSceneGraph() -> SceneGraph {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal is not available.")
        }
        let root = SceneGraph.Node(label: "Root")

        // Lighting: a soft fill plus a spot light that casts shadows onto the floor.
        let fill = SceneGraph.Node(parent: root, content: .light(Light(type: .point, intensity: 15, range: 50, castsShadow: false)))
        fill.trs.translation = [-5, 4, 4]
        let spot = SceneGraph.Node(parent: root, content: .light(Light(type: .spot, intensity: 80, range: 30, outerConeAngle: .pi / 4)))
        spot.trs.translation = [3, 7, 3]
        spot.look(at: .zero)

        // Distance fog fades the far edge of the floor into the background.
        root.addShape(.floor(width: 30, length: 30), material([0.4, 0.42, 0.45], shininess: 4), at: [0, -1, 0], device: device)

        // Hierarchy: the moon is a child of a pivot, which is a child of the planet. Turning the pivot orbits the moon.
        let planet = root.addShape(.sphere(radius: 0.6), material([0.2, 0.45, 0.9], shininess: 64), at: [0, 0.4, 0], device: device)
        let moonPivot = SceneGraph.Node(parent: planet, label: "Moon Pivot")
        moonPivot.addShape(.sphere(radius: 0.15), material([0.8, 0.8, 0.75]), at: [1.1, 0, 0], device: device)
        moonPivot.run(.repeatForever(.rotate(by: 2 * .pi, around: [0, 1, 0.2], duration: 6)))

        // Emission: a glowing bulb that carries its own warm point light around the scene.
        let bulbPivot = SceneGraph.Node(parent: root, label: "Bulb Pivot")
        let bulb = SceneGraph.Node(parent: bulbPivot, content: .light(Light(type: .point, color: [1, 0.6, 0.2], intensity: 6, range: 6, castsShadow: false)))
        bulb.trs.translation = [2.5, 1.2, 0]
        bulb.addShape(.sphere(radius: 0.1), material([1, 0.6, 0.2], emission: [1, 0.6, 0.2]), device: device)
        bulbPivot.run(.repeatForever(.rotate(by: -2 * .pi, around: [0, 1, 0], duration: 9)))

        // Look-at constraint: the cone always points at the bulb.
        let pointer = SceneGraph.Node(parent: root, label: "Pointer")
        pointer.trs.translation = [-2, -0.5, -1]
        pointer.constraints = [.lookAt(target: bulb)]
        let cone = pointer.addShape(.cone(bottomRadius: 0.25, height: 0.7), material([0.95, 0.8, 0.2]), device: device)
        cone.trs.rotation = simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])

        // Sequence, group and easing: a box that squashes, hops and lands.
        let hopper = root.addShape(.box(width: 0.5, height: 0.5, length: 0.5), material([0.9, 0.25, 0.25]), at: [2, -0.75, -1], device: device)
        let squash = SceneGraph.Action.scale(to: [1.3, 0.6, 1.3], duration: 0.25).timingMode(.easeOut)
        let stretch = SceneGraph.Action.scale(to: [0.85, 1.25, 0.85], duration: 0.2)
        let rise = SceneGraph.Action.move(by: [0, 1.2, 0], duration: 0.45).timingMode(.easeOut)
        hopper.run(.repeatForever(.sequence([
            squash, .group([stretch, rise, .rotate(by: .pi / 2, around: [0, 1, 0], duration: 0.9)]),
            rise.reversed(), squash, .scale(to: [1, 1, 1], duration: 0.2), .wait(duration: 0.6),
        ])))

        // Opacity: a glass torus that fades out and back in.
        let glass = root.addShape(.torus(ringRadius: 0.4, pipeRadius: 0.12), material([0.6, 0.9, 0.8], shininess: 128, opacity: 0.5), at: [-2, 0.2, 1.5], device: device)
        glass.run(.repeatForever(.group([
            .rotateBy(x: 2 * .pi, y: 0, z: .pi, duration: 8),
            .sequence([.fadeOut(duration: 2), .fadeIn(duration: 2)]),
        ])))

        // Custom action: per-frame code that wobbles the teapot's tilt.
        let teapot = root.addShape(.teapot(diameter: 0.8), material([0.75, 0.5, 0.85], shininess: 64), at: [0, -0.75, 2], device: device)
        teapot.run(.repeatForever(.custom(duration: 3) { node, elapsed in
            let phase = elapsed / 3 * 2 * .pi
            node.trs.rotation = simd_quatf(angle: sin(phase) * 0.3, axis: [0, 0, 1]) * simd_quatf(angle: phase, axis: [0, 1, 0])
        }))

        // Billboard constraint: the title always faces the camera.
        let title = root.addShape(.text("Hello, World", fontSize: 0.4, extrusionDepth: 0.08), material([0.95, 0.95, 0.95]), at: [0, 2, 0], device: device)
        title.constraints = [.billboard(freeAxes: .y)]

        let camera = SceneGraph.Node(parent: root, label: "Camera", content: .camera(SceneView.defaultCamera))
        camera.trs.translation = [0, 2.5, 7]
        camera.look(at: [0, 0.3, 0])

        let sceneGraph = SceneGraph(root: root)
        sceneGraph.fog = SceneGraph.Fog(color: [0.12, 0.13, 0.16, 1], startDistance: 8, endDistance: 20)
        return sceneGraph
    }
}

extension SceneGraph.Node {
    @discardableResult
    func addShape(_ shape: SceneGraph.Shape, _ material: any SceneSprockets.Material, at position: SIMD3<Float> = .zero, device: MTLDevice) -> SceneGraph.Node {
        let node = SceneGraph.Node(parent: self, shape: shape, material: material, device: device)
        node.trs.translation = position
        return node
    }
}

#Preview {
    ContentView()
}
