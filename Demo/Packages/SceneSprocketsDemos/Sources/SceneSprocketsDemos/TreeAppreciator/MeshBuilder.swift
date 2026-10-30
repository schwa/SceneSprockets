import Metal
import SceneSprockets
import SceneSprocketsBlinnPhong
import simd
import SwiftMesh

// Collects flat-shaded triangles into one mesh with a submesh per material.
final class MeshBuilder {
    private var positions: [SIMD3<Float>] = []
    private var normals: [SIMD3<Float>] = []
    private var groups: [String: [UInt32]] = [:]
    private var materials: [String: BlinnPhongSceneMaterial] = [:]
    private var order: [String] = []

    func material(_ key: String, _ make: () -> BlinnPhongSceneMaterial) {
        guard materials[key] == nil else {
            return
        }
        materials[key] = make()
        order.append(key)
        groups[key] = []
    }

    // Normal points away from `center`.
    func triangle(_ key: String, _ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>, outwardFrom center: SIMD3<Float>) {
        var normal = simd_cross(b - a, c - a)
        guard simd_length_squared(normal) > 1e-12 else {
            return
        }
        normal = simd_normalize(normal)
        if simd_dot(normal, (a + b + c) / 3 - center) < 0 {
            normal = -normal
        }
        let start = UInt32(positions.count)
        positions += [a, b, c]
        normals += [normal, normal, normal]
        groups[key, default: []] += [start, start + 1, start + 2]
    }

    func frustum(_ key: String, from a: SIMD3<Float>, to b: SIMD3<Float>, radiusA: Float, radiusB: Float, sides: Int = 7) {
        let axis = simd_normalize(b - a)
        let reference: SIMD3<Float> = abs(axis.y) < 0.9 ? [0, 1, 0] : [1, 0, 0]
        let u = simd_normalize(simd_cross(axis, reference))
        let v = simd_cross(axis, u)
        func ring(_ center: SIMD3<Float>, _ radius: Float) -> [SIMD3<Float>] {
            (0..<sides).map { index in
                let angle = Float(index) / Float(sides) * 2 * .pi
                return center + (u * cos(angle) + v * sin(angle)) * radius
            }
        }
        let lower = ring(a, radiusA)
        let upper = ring(b, radiusB)
        let middle = (a + b) / 2
        for index in 0..<sides {
            let next = (index + 1) % sides
            triangle(key, lower[index], lower[next], upper[next], outwardFrom: middle)
            triangle(key, lower[index], upper[next], upper[index], outwardFrom: middle)
        }
    }

    func icosahedron(_ key: String, center: SIMD3<Float>, scale: SIMD3<Float>, rotation: simd_quatf = simd_quatf(angle: 0, axis: [0, 1, 0])) {
        let points = Self.icosahedronVertices.map { center + rotation.act($0 * scale) }
        for face in Self.icosahedronFaces {
            triangle(key, points[face.0], points[face.1], points[face.2], outwardFrom: center)
        }
    }

    func cone(_ key: String, base: SIMD3<Float>, tip: SIMD3<Float>, radius: Float, sides: Int = 5) {
        let axis = simd_normalize(tip - base)
        let reference: SIMD3<Float> = abs(axis.y) < 0.9 ? [0, 1, 0] : [1, 0, 0]
        let u = simd_normalize(simd_cross(axis, reference))
        let v = simd_cross(axis, u)
        let ring = (0..<sides).map { index -> SIMD3<Float> in
            let angle = Float(index) / Float(sides) * 2 * .pi
            return base + (u * cos(angle) + v * sin(angle)) * radius
        }
        let center = base + (tip - base) * 0.3
        for index in 0..<sides {
            triangle(key, ring[index], ring[(index + 1) % sides], tip, outwardFrom: center)
        }
    }

    func appendRaw(_ key: String, positions newPositions: [SIMD3<Float>], normals newNormals: [SIMD3<Float>], indices: [UInt32]) {
        let start = UInt32(positions.count)
        positions += newPositions
        normals += newNormals
        groups[key, default: []] += indices.map { $0 + start }
    }

    var isEmpty: Bool {
        positions.isEmpty
    }

    func build(device: MTLDevice, label: String) -> (MetalMesh, [any SceneSprockets.Material])? {
        let used = order.filter { !(groups[$0]?.isEmpty ?? true) }
        guard !used.isEmpty else {
            return nil
        }
        let textureCoordinates = [SIMD2<Float>](repeating: .zero, count: positions.count)
        let mesh = MetalMesh(
            device: device,
            attributes: [.positions(positions), .normals(normals), .textureCoordinates(textureCoordinates)],
            submeshes: used.map { MetalMesh.SubmeshIndices(label: $0, indices: groups[$0]!) },
            label: label
        )
        return (mesh, used.map { materials[$0]! })
    }

    private static let icosahedronVertices: [SIMD3<Float>] = {
        let t = (1 + sqrt(Float(5))) / 2
        let raw: [SIMD3<Float>] = [
            [-1, t, 0], [1, t, 0], [-1, -t, 0], [1, -t, 0],
            [0, -1, t], [0, 1, t], [0, -1, -t], [0, 1, -t],
            [t, 0, -1], [t, 0, 1], [-t, 0, -1], [-t, 0, 1],
        ]
        return raw.map(simd_normalize)
    }()

    private static let icosahedronFaces: [(Int, Int, Int)] = [
        (0, 11, 5), (0, 5, 1), (0, 1, 7), (0, 7, 10), (0, 10, 11),
        (1, 5, 9), (5, 11, 4), (11, 10, 2), (10, 7, 6), (7, 1, 8),
        (3, 9, 4), (3, 4, 2), (3, 2, 6), (3, 6, 8), (3, 8, 9),
        (4, 9, 5), (2, 4, 11), (6, 2, 10), (8, 6, 7), (9, 8, 1),
    ]
}

func matte(_ color: SIMD3<Float>, shininess: Float = 8, specular: Float = 0.05) -> BlinnPhongSceneMaterial {
    BlinnPhongSceneMaterial(ambient: .color(color), diffuse: .color(color), specular: .color(specular), shininess: shininess)
}

func glowing(_ color: SIMD3<Float>) -> BlinnPhongSceneMaterial {
    BlinnPhongSceneMaterial(ambient: .color(0), diffuse: .color(0), specular: .color(0), shininess: 1, emission: .color(color))
}
