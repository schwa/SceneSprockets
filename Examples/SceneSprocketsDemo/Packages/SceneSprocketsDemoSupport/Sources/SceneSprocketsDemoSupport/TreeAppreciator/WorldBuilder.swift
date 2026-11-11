import GeometryLite3D
import Metal
import SceneSprockets
import SceneSprocketsBlinnPhong
import simd
import SwiftMesh

let sunDirection = simd_normalize(SIMD3<Float>(0.5, 0.45, -0.8))

struct World {
    var sceneGraph: SceneGraph
    // Sways in the wind; rings for found differences are its children.
    var treeNode: SceneGraph.Node
}

@MainActor
func makeWorld(tree: GrownTree, species: Species, season: Season, seed: UInt32, device: MTLDevice) -> World {
    let root = SceneGraph.Node(label: "Root")

    let sun = root.addChild(SceneGraph.Node(label: "Sun", content: .light(Light(type: .directional, color: season.sun, intensity: 2.4))))
    sun.transform = Transform3D(storing: LookAt(position: sunDirection * 30, target: .zero, up: [0, 1, 0]).cameraMatrix)
    let fill = root.addChild(SceneGraph.Node(label: "Fill", content: .light(Light(type: .directional, color: [0.55, 0.65, 0.9], intensity: 0.35))))
    fill.transform = Transform3D(storing: LookAt(position: [-8, 4, 10], target: .zero, up: [0, 1, 0]).cameraMatrix)

    if let sky = makeSky(season: season, device: device) {
        root.addChild(SceneGraph.Node(label: "Sky", content: .mesh(sky.0, materials: sky.1, castsShadow: false, receivesShadow: false)))
    }
    let sunDisc = MeshBuilder()
    sunDisc.material("sun") { glowing([1.4, 1.25, 1.0]) }
    sunDisc.icosahedron("sun", center: sunDirection * 140, scale: SIMD3(repeating: 5))
    if let (mesh, materials) = sunDisc.build(device: device, label: "Sun Disc") {
        root.addChild(SceneGraph.Node(label: "Sun Disc", content: .mesh(mesh, materials: materials, castsShadow: false, receivesShadow: false)))
    }

    if let (mesh, materials) = makeGround(season: season, seed: seed).build(device: device, label: "Ground") {
        root.addChild(SceneGraph.Node(label: "Ground", content: .mesh(mesh, materials: materials, castsShadow: false, receivesShadow: true)))
    }
    if let (mesh, materials) = makeMeadow(season: season, seed: seed).build(device: device, label: "Meadow") {
        root.addChild(SceneGraph.Node(label: "Meadow", content: .mesh(mesh, materials: materials, castsShadow: true, receivesShadow: true)))
    }

    let treeNode = root.addChild(SceneGraph.Node(label: "Tree"))
    if let (mesh, materials) = makeTreeMesh(tree: tree, species: species, season: season).build(device: device, label: "Tree") {
        treeNode.addChild(SceneGraph.Node(label: "Tree Mesh", content: .mesh(mesh, materials: materials, castsShadow: true, receivesShadow: true)))
    }
    addAtmosphere(to: root, tree: tree, season: season, seed: seed)
    return World(sceneGraph: SceneGraph(root: root), treeNode: treeNode)
}

func makeTreeMesh(tree: GrownTree, species: Species, season: Season) -> MeshBuilder {
    let builder = MeshBuilder()
    builder.material("bark") { matte(species.bark) }
    for branch in tree.branches {
        builder.frustum("bark", from: branch.a, to: branch.b, radiusA: branch.radiusA, radiusB: branch.radiusB * 0.98)
        builder.icosahedron("bark", center: branch.b, scale: SIMD3(repeating: branch.radiusB * 0.95))
    }
    let shades: [Float] = [0.82, 1, 1.18]
    for leaf in tree.leaves {
        let base = leaf.paletteIndex < 0 ? season.tint : season.leaves[leaf.paletteIndex]
        let key = "leaf \(leaf.paletteIndex) \(leaf.shade)"
        builder.material(key) { matte(base * shades[leaf.shade], shininess: 12, specular: 0.08) }
        let rotation = simd_quatf(angle: leaf.rotation, axis: [0, 1, 0]) * simd_quatf(angle: leaf.rotation * 1.7, axis: [1, 0, 0])
        builder.icosahedron(key, center: leaf.position, scale: [leaf.size, leaf.size * 0.8, leaf.size], rotation: rotation)
    }
    builder.material("fruit") { matte(linearColor(0xD62F2F), shininess: 40, specular: 0.4) }
    for fruit in tree.fruits {
        builder.icosahedron("fruit", center: fruit.position, scale: SIMD3(repeating: fruit.size))
    }
    builder.material("blossom") { BlinnPhongSceneMaterial(ambient: .color(linearColor(0xFFD1E3)), diffuse: .color(linearColor(0xFFD1E3)), specular: .color(0.1), shininess: 10, emission: .color(linearColor(0x553344))) }
    for blossom in tree.blossoms {
        builder.icosahedron("blossom", center: blossom.position, scale: [blossom.size, blossom.size * 0.45, blossom.size], rotation: simd_quatf(angle: blossom.rotation, axis: [0, 1, 0]))
    }
    builder.material("beak") { matte(linearColor(0xF2A93B)) }
    for (index, bird) in tree.birds.enumerated() {
        let key = "bird \(index)"
        builder.material(key) { matte(bird.color, shininess: 20, specular: 0.2) }
        let rotation = simd_quatf(angle: bird.yaw, axis: [0, 1, 0])
        func place(_ local: SIMD3<Float>) -> SIMD3<Float> { bird.position + rotation.act(local) }
        builder.icosahedron(key, center: place([0, 0, 0]), scale: [0.2, 0.17, 0.28], rotation: rotation)
        builder.icosahedron(key, center: place([0, 0.17, 0.2]), scale: SIMD3(repeating: 0.13), rotation: rotation)
        builder.icosahedron(key, center: place([0, 0.05, -0.32]), scale: [0.09, 0.03, 0.18], rotation: rotation)
        builder.cone("beak", base: place([0, 0.16, 0.3]), tip: place([0, 0.15, 0.45]), radius: 0.05)
    }
    return builder
}

private func groundHeight(_ x: Float, _ z: Float) -> Float {
    let distance = hypot(x, z)
    guard distance > 20 else {
        return 0
    }
    return sin(x * 0.07) * cos(z * 0.05) * min((distance - 20) * 0.08, 4) + (distance - 20) * 0.02
}

func makeGround(season: Season, seed: UInt32) -> MeshBuilder {
    let builder = MeshBuilder()
    let shades: [Float] = [0.95, 1, 1.04]
    for (index, shade) in shades.enumerated() {
        builder.material("ground \(index)") { matte(season.ground * shade, shininess: 2, specular: 0) }
    }
    var random = SeededRandom("ground\(seed)")
    let size: Float = 240
    let segments = 90
    let step = size / Float(segments)
    func point(_ i: Int, _ j: Int) -> SIMD3<Float> {
        let x = -size / 2 + Float(i) * step
        let z = -size / 2 + Float(j) * step
        return [x, groundHeight(x, z), z]
    }
    for i in 0..<segments {
        for j in 0..<segments {
            let a = point(i, j), b = point(i + 1, j), c = point(i + 1, j + 1), d = point(i, j + 1)
            let noise = sin(a.x * 0.4) * cos(a.z * 0.3) + random.signed()
            let key = "ground \(noise < -0.3 ? 0 : noise > 0.3 ? 2 : 1)"
            let below = (a + c) / 2 - [0, 10, 0]
            builder.triangle(key, a, b, c, outwardFrom: below)
            builder.triangle(key, a, c, d, outwardFrom: below)
        }
    }
    return builder
}

func makeMeadow(season: Season, seed: UInt32) -> MeshBuilder {
    let builder = MeshBuilder()
    var random = SeededRandom("meadow\(seed)")
    let grassShades: [Float] = [0.6, 0.72, 0.85]
    for (index, shade) in grassShades.enumerated() {
        let grass = season.name == "Winter" ? linearColor(0x8FA88A) : season.ground
        builder.material("grass \(index)") { matte(grass * shade, shininess: 4, specular: 0.02) }
    }
    for _ in 0..<700 {
        let angle = random.next() * 6.28
        let distance = 2 + pow(random.next(), 0.7) * 38
        let base = SIMD3<Float>(cos(angle) * distance, 0, sin(angle) * distance)
        let height = 0.3 + random.next() * 0.5
        let lean = SIMD3<Float>(random.signed(), 0, random.signed()) * 0.2
        builder.cone("grass \(min(Int(random.next() * 3), 2))", base: base, tip: base + [0, height, 0] + lean, radius: 0.06 + random.next() * 0.05, sides: 3)
    }
    builder.material("stone") { matte(linearColor(0x9A9890), shininess: 6, specular: 0.05) }
    for _ in 0..<40 {
        let angle = random.next() * 6.28
        let distance = 5 + random.next() * 30
        let size = 0.2 + random.next() * 0.6
        builder.icosahedron("stone", center: [cos(angle) * distance, 0, sin(angle) * distance], scale: [size, size * 0.6, size], rotation: simd_quatf(angle: random.next() * 6, axis: simd_normalize([random.signed(), 1, random.signed()])))
    }
    if season.hasFlowers {
        let colors: [UInt32] = [0xFFFFFF, 0xFFD84D, 0xE98AB0, 0xA59BFF]
        for (index, color) in colors.enumerated() {
            builder.material("flower \(index)") { BlinnPhongSceneMaterial(ambient: .color(linearColor(color)), diffuse: .color(linearColor(color)), specular: .color(0), shininess: 1, emission: .color(linearColor(color) * 0.25)) }
        }
        for _ in 0..<160 {
            let angle = random.next() * 6.28
            let distance = 3 + random.next() * 25
            builder.icosahedron("flower \(min(Int(random.next() * 4), 3))", center: [cos(angle) * distance, 0.3, sin(angle) * distance], scale: SIMD3(repeating: 0.09))
        }
    }
    return builder
}

// An inside-out sphere whose emission is a vertical gradient texture.
func makeSky(season: Season, device: MTLDevice) -> (MetalMesh, [any SceneSprockets.Material])? {
    let height = 128
    var pixels = [UInt8](repeating: 255, count: height * 4)
    func encode(_ linear: Float) -> UInt8 {
        let c = max(0, min(1, linear))
        let srgb = c <= 0.0031308 ? c * 12.92 : 1.055 * pow(c, 1 / 2.4) - 0.055
        return UInt8(srgb * 255)
    }
    for row in 0..<height {
        // Row 0 is the top of the sky (v = 0).
        let y = 1 - Float(row) / Float(height - 1) * 2
        let t = pow(max(0, min(1, y * 1.4 + 0.15)), 0.8)
        let color = simd_mix(season.skyHorizon, season.skyTop, SIMD3(repeating: t))
        pixels[row * 4] = encode(color.x)
        pixels[row * 4 + 1] = encode(color.y)
        pixels[row * 4 + 2] = encode(color.z)
    }
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm_srgb, width: 1, height: height, mipmapped: false)
    descriptor.usage = .shaderRead
    descriptor.storageMode = .shared
    guard let texture = device.makeTexture(descriptor: descriptor) else {
        return nil
    }
    texture.replace(region: MTLRegionMake2D(0, 0, 1, height), mipmapLevel: 0, withBytes: pixels, bytesPerRow: 4)

    let radius: Float = 180
    let rings = 32, segments = 48
    var positions: [SIMD3<Float>] = []
    var normals: [SIMD3<Float>] = []
    var coordinates: [SIMD2<Float>] = []
    for ring in 0...rings {
        let v = Float(ring) / Float(rings)
        let phi = v * .pi
        for segment in 0...segments {
            let theta = Float(segment) / Float(segments) * 2 * .pi
            let direction = SIMD3<Float>(sin(phi) * cos(theta), cos(phi), sin(phi) * sin(theta))
            positions.append(direction * radius)
            normals.append(-direction)
            coordinates.append([0.5, v])
        }
    }
    var indices: [UInt32] = []
    for ring in 0..<rings {
        for segment in 0..<segments {
            let a = UInt32(ring * (segments + 1) + segment)
            let b = a + UInt32(segments + 1)
            indices += [a, a + 1, b, a + 1, b + 1, b]
        }
    }
    let sampler = MTLSamplerDescriptor()
    sampler.minFilter = .linear
    sampler.magFilter = .linear
    sampler.sAddressMode = .clampToEdge
    sampler.tAddressMode = .clampToEdge
    sampler.supportArgumentBuffers = true
    let mesh = MetalMesh(device: device, attributes: [.positions(positions), .normals(normals), .textureCoordinates(coordinates)], submeshes: [.init(label: "Sky", indices: indices)], label: "Sky")
    let material = BlinnPhongSceneMaterial(ambient: .color(0), diffuse: .color(0), specular: .color(0), shininess: 1, emission: .texture(texture, sampler: sampler))
    return (mesh, [material])
}
