import simd
import SwiftMesh

// Mesh helpers for the keynote's Deformation slide.
enum DeformationMeshes {
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
