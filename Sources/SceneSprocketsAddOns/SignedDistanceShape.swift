import Metal
import simd
import SwiftMesh

/// A shape described by a signed distance function: primitives combined with smooth union, subtraction and
/// intersection, such as metaballs that merge when they move close together.
///
/// ``makeMesh(device:cellSize:)`` turns the shape into an ordinary mesh, so it is lit, depth-tested and shadowed like
/// any other mesh, with any material. Make a new mesh when the shape changes.
public indirect enum SignedDistanceShape: Sendable, Equatable {
    /// A sphere.
    case sphere(center: SIMD3<Float>, radius: Float)
    /// A box with rounded edges. `cornerRadius` is inside `halfExtents`.
    case box(center: SIMD3<Float>, halfExtents: SIMD3<Float>, cornerRadius: Float = 0)
    /// A capsule: a cylinder from `from` to `to` with hemispherical ends.
    case capsule(from: SIMD3<Float>, to: SIMD3<Float>, radius: Float)
    /// All the shapes together. A `smoothness` above 0 blends them where they come within that distance.
    case union([Self], smoothness: Float = 0)
    /// `shape` with `removing` cut away, blended over `smoothness`.
    case subtraction(Self, removing: Self, smoothness: Float = 0)
    /// Only where all the shapes overlap, blended over `smoothness`.
    case intersection([Self], smoothness: Float = 0)

    /// The signed distance from `point` to the surface: negative inside, positive outside.
    ///
    /// Smooth combinations make it an estimate near the blended parts, which is enough for meshing.
    public func distance(at point: SIMD3<Float>) -> Float {
        switch self {
        case let .sphere(center, radius):
            return simd_length(point - center) - radius

        case let .box(center, halfExtents, cornerRadius):
            let rounding = min(cornerRadius, halfExtents.min())
            let offset = abs(point - center) - (halfExtents - rounding)
            return simd_length(simd_max(offset, .zero)) + min(offset.max(), 0) - rounding

        case let .capsule(from, to, radius):
            let axis = to - from
            let lengthSquared = simd_length_squared(axis)
            let t = lengthSquared > 0 ? simd_clamp(simd_dot(point - from, axis) / lengthSquared, 0, 1) : 0
            return simd_length(point - (from + axis * t)) - radius

        case let .union(shapes, smoothness):
            return shapes.map { $0.distance(at: point) }.reduce(nil) { result, distance in
                result.map { Self.smoothMinimum($0, distance, smoothness) } ?? distance
            } ?? .greatestFiniteMagnitude

        case let .subtraction(shape, removing, smoothness):
            return -Self.smoothMinimum(-shape.distance(at: point), removing.distance(at: point), smoothness)

        case let .intersection(shapes, smoothness):
            return shapes.map { $0.distance(at: point) }.reduce(nil) { result, distance in
                result.map { -Self.smoothMinimum(-$0, -distance, smoothness) } ?? distance
            } ?? .greatestFiniteMagnitude
        }
    }

    /// The outward surface direction at `point`, from the distance field's gradient.
    public func normal(at point: SIMD3<Float>) -> SIMD3<Float> {
        let step: Float = 1e-3
        let gradient = SIMD3<Float>(
            distance(at: point + [step, 0, 0]) - distance(at: point - [step, 0, 0]),
            distance(at: point + [0, step, 0]) - distance(at: point - [0, step, 0]),
            distance(at: point + [0, 0, step]) - distance(at: point - [0, 0, step])
        )
        let length = simd_length(gradient)
        return length > 0 ? gradient / length : [0, 1, 0]
    }

    /// A box that contains the shape, or `nil` for an empty shape.
    public var bounds: (min: SIMD3<Float>, max: SIMD3<Float>)? {
        switch self {
        case let .sphere(center, radius):
            return (center - radius, center + radius)

        case let .box(center, halfExtents, _):
            return (center - halfExtents, center + halfExtents)

        case let .capsule(from, to, radius):
            return (simd_min(from, to) - radius, simd_max(from, to) + radius)

        case let .union(shapes, smoothness):
            // Smooth blending can bulge out by up to a quarter of the smoothness.
            let all = shapes.compactMap(\.bounds)
            guard let first = all.first else {
                return nil
            }
            let combined = all.dropFirst().reduce(first) { (simd_min($0.min, $1.min), simd_max($0.max, $1.max)) }
            return (combined.min - smoothness / 4, combined.max + smoothness / 4)

        case let .subtraction(shape, _, _):
            return shape.bounds

        case let .intersection(shapes, _):
            let all = shapes.compactMap(\.bounds)
            guard all.count == shapes.count, let first = all.first else {
                return nil
            }
            let combined = all.dropFirst().reduce(first) { (simd_max($0.min, $1.min), simd_min($0.max, $1.max)) }
            return combined.min.x <= combined.max.x && combined.min.y <= combined.max.y && combined.min.z <= combined.max.z ? combined : nil
        }
    }

    // Polynomial smooth minimum (Inigo Quilez). Equal to min when `smoothness` is 0.
    static func smoothMinimum(_ a: Float, _ b: Float, _ smoothness: Float) -> Float {
        guard smoothness > 0 else {
            return min(a, b)
        }
        let h = max(smoothness - abs(a - b), 0) / smoothness
        return min(a, b) - h * h * smoothness / 4
    }
}

public extension SignedDistanceShape {
    /// Positions, normals and triangle indices of the shape's surface, sampled on a grid of `cellSize` cubes.
    ///
    /// Smaller cells give a finer surface and take longer: the time grows with the cube of the shape's size divided by
    /// `cellSize`.
    func surface(cellSize: Float) -> (positions: [SIMD3<Float>], normals: [SIMD3<Float>], indices: [UInt32]) {
        guard cellSize > 0, let bounds else {
            return ([], [], [])
        }
        // One empty cell on each side, so the surface closes at the edge of the grid.
        let origin = bounds.min - cellSize
        let counts = SIMD3<Int>(((bounds.max - bounds.min) / cellSize).rounded(.up)) &+ 2
        let corners = counts &+ 1
        func index(_ x: Int, _ y: Int, _ z: Int) -> Int {
            (z * corners.y + y) * corners.x + x
        }
        var samples = [Float](repeating: 0, count: corners.x * corners.y * corners.z)
        for z in 0..<corners.z {
            for y in 0..<corners.y {
                for x in 0..<corners.x {
                    samples[index(x, y, z)] = distance(at: origin + SIMD3<Float>(Float(x), Float(y), Float(z)) * cellSize)
                }
            }
        }

        var positions: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        func emit(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>) {
            let faceNormal = simd_cross(b - a, c - a)
            // Corners on the surface make slivers with no area and no reliable winding.
            let minimumArea = cellSize * cellSize * 1e-6
            guard simd_length(faceNormal) > minimumArea else {
                return
            }
            // Wind counter-clockwise seen from outside.
            let outward = simd_dot(faceNormal, normal(at: (a + b + c) / 3)) >= 0
            let start = UInt32(positions.count)
            positions += outward ? [a, b, c] : [a, c, b]
            indices += [start, start + 1, start + 2]
        }

        for z in 0..<counts.z {
            for y in 0..<counts.y {
                for x in 0..<counts.x {
                    var cubePositions: [SIMD3<Float>] = []
                    var cubeValues: [Float] = []
                    var inside = 0
                    for corner in Self.cubeCorners {
                        let gridPoint = SIMD3<Int>(x, y, z) &+ corner
                        let value = samples[index(gridPoint.x, gridPoint.y, gridPoint.z)]
                        cubePositions.append(origin + SIMD3<Float>(gridPoint) * cellSize)
                        cubeValues.append(value)
                        inside += value < 0 ? 1 : 0
                    }
                    guard inside > 0, inside < 8 else {
                        continue
                    }
                    for tetrahedron in Self.cubeTetrahedra {
                        Self.polygonize(tetrahedron.map { (cubePositions[$0], cubeValues[$0]) }, emit: emit)
                    }
                }
            }
        }
        return (positions, positions.map { normal(at: $0) }, indices)
    }

    /// A mesh of the shape's surface, sampled on a grid of `cellSize` cubes, or `nil` when the shape has no surface.
    ///
    /// The mesh has positions, normals and texture coordinates (all zero), the layout the material renderers read.
    func makeMesh(device: MTLDevice, cellSize: Float) -> MetalMesh? {
        let surface = surface(cellSize: cellSize)
        guard !surface.indices.isEmpty else {
            return nil
        }
        return MetalMesh(
            device: device,
            attributes: [.positions(surface.positions), .normals(surface.normals), .textureCoordinates(Array(repeating: .zero, count: surface.positions.count))],
            submeshes: [MetalMesh.SubmeshIndices(label: "Surface", indices: surface.indices)],
            label: "Signed Distance Shape"
        )
    }

    private static let cubeCorners: [SIMD3<Int>] = [
        [0, 0, 0], [1, 0, 0], [1, 1, 0], [0, 1, 0],
        [0, 0, 1], [1, 0, 1], [1, 1, 1], [0, 1, 1]
    ]

    // Six tetrahedra around the cube's 0-6 diagonal. Marching tetrahedra needs no case tables.
    private static let cubeTetrahedra: [[Int]] = [
        [0, 5, 1, 6], [0, 1, 2, 6], [0, 2, 3, 6], [0, 3, 7, 6], [0, 7, 4, 6], [0, 4, 5, 6]
    ]

    private static func polygonize(_ corners: [(position: SIMD3<Float>, value: Float)], emit: (SIMD3<Float>, SIMD3<Float>, SIMD3<Float>) -> Void) {
        let insideCorners = corners.indices.filter { corners[$0].value < 0 }
        let outsideCorners = corners.indices.filter { corners[$0].value >= 0 }
        func crossing(_ a: Int, _ b: Int) -> SIMD3<Float> {
            let (first, second) = (corners[a], corners[b])
            let t = first.value / (first.value - second.value)
            return first.position + (second.position - first.position) * t
        }
        switch insideCorners.count {
        case 1, 3:
            // One corner on its own side: one triangle across its three edges.
            let lone = insideCorners.count == 1 ? insideCorners[0] : outsideCorners[0]
            let others = corners.indices.filter { $0 != lone }
            emit(crossing(lone, others[0]), crossing(lone, others[1]), crossing(lone, others[2]))

        case 2:
            // Two on each side: a quad across the four edges between them.
            let (a, b) = (insideCorners[0], insideCorners[1])
            let (c, d) = (outsideCorners[0], outsideCorners[1])
            let quad = [crossing(a, c), crossing(a, d), crossing(b, d), crossing(b, c)]
            emit(quad[0], quad[1], quad[2])
            emit(quad[0], quad[2], quad[3])

        default:
            break
        }
    }
}
