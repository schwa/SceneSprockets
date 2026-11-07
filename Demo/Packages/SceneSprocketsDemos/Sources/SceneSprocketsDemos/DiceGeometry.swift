import CoreGraphics
import CoreText
import Foundation
import simd
import SwiftMesh

// Dice built from scratch: the polyhedron, its faces' numbers in a texture atlas (a mask: white numbers on clear), and
// a normal map that engraves the numbers. A D6 is 8 units across; the demo scales the dice down.
struct DiceGeometry {
    var mesh: Mesh
    var mask: CGImage
    var normalMap: CGImage

    static let atlasSize = 1_024

    init(_ kind: DiceDemo.Kind) {
        let solid = Self.solid(kind)
        let faces = Self.faces(of: solid.vertices)
        let labels = Self.labels(kind, faces: faces, vertices: solid.vertices)
        let columns = Int(ceil(sqrt(Double(faces.count))))
        let rows = Int(ceil(Double(faces.count) / Double(columns)))
        let cell = Float(Self.atlasSize) / Float(max(columns, rows))

        // Each face is laid flat into its own atlas cell. Corners are not shared, so the mesh has per-face vertices.
        var positions: [SIMD3<Float>] = []
        var meshFaces: [[Int]] = []
        var uvs: [SIMD2<Float>] = []
        var layouts: [FaceLayout] = []
        for (index, face) in faces.enumerated() {
            let points = face.map { solid.vertices[$0] }
            let centroid = points.reduce(.zero, +) / Float(points.count)
            let normal = simd_normalize(simd_cross(points[1] - points[0], points[2] - points[0]))
            // "Up" in the cell points at the first corner, so numbers read toward a vertex; on squares, at an edge.
            let up = simd_normalize((kind == .d6 ? (points[0] + points[1]) / 2 : points[0]) - centroid)
            // Seen from outside, right is up turned clockwise about the normal.
            let right = simd_cross(normal, up)
            let flat = points.map { SIMD2(simd_dot($0 - centroid, right), simd_dot($0 - centroid, up)) }
            let radius = flat.map(simd_length).max() ?? 1
            let center = SIMD2(Float(index % columns) + 0.5, Float(index / columns) + 0.5) * cell
            let scale = cell * 0.46 / radius
            let corners = flat.map { center + $0 * scale }
            layouts.append(FaceLayout(center: center, corners: corners, scale: scale, inradius: Self.inradius(flat) * scale))
            meshFaces.append(Array(positions.count..<(positions.count + points.count)))
            positions += points
            // Atlas pixels have y up; texture coordinates have v down.
            uvs += corners.map { SIMD2($0.x / Float(Self.atlasSize), 1 - $0.y / Float(Self.atlasSize)) }
        }
        var mesh = Mesh(positions: positions, faces: meshFaces).withFlatNormals()
        // No vertex is shared between faces, so each corner's vertex picks its coordinates.
        mesh.textureCoordinates = mesh.topology.halfEdges.map { uvs[$0.origin.raw] }
        self.mesh = mesh
        let height = Self.drawMask(kind, layouts: layouts, labels: labels)
        mask = height.mask
        normalMap = Self.normalMap(height: height.alpha)
    }

    private struct FaceLayout {
        var center: SIMD2<Float>
        var corners: [SIMD2<Float>]
        var scale: Float
        var inradius: Float
    }

    // MARK: Solids

    static func solid(_ kind: DiceDemo.Kind) -> (vertices: [SIMD3<Float>], circumradius: Float) {
        let phi = (1 + sqrt(Float(5))) / 2
        let vertices: [SIMD3<Float>]
        let circumradius: Float
        switch kind {
        case .d4:
            vertices = [[1, 1, 1], [1, -1, -1], [-1, 1, -1], [-1, -1, 1]]
            circumradius = 5.4
        case .d6:
            vertices = [-1, 1].flatMap { x in [-1, 1].flatMap { y in [-1, 1].map { z in SIMD3<Float>(x, y, z) } } }
            circumradius = 4 * sqrt(3)
        case .d8:
            vertices = [[1, 0, 0], [-1, 0, 0], [0, 1, 0], [0, -1, 0], [0, 0, 1], [0, 0, -1]]
            circumradius = 5.4
        case .d10:
            // A pentagonal trapezohedron. The apex height makes each kite planar.
            let ring: Float = 0.1056
            let apex = ring * (1 + cos(.pi / 5)) / (1 - cos(.pi / 5))
            var points: [SIMD3<Float>] = [[0, apex, 0], [0, -apex, 0]]
            for index in 0..<10 {
                let angle = Float(index) * .pi / 5
                points.append([cos(angle), index.isMultiple(of: 2) ? ring : -ring, sin(angle)])
            }
            vertices = points
            circumradius = 5.5
        case .d12:
            var points: [SIMD3<Float>] = [-1, 1].flatMap { x in [-1, 1].flatMap { y in [-1, 1].map { z in SIMD3<Float>(x, y, z) } } }
            for a in [-1, 1] as [Float] {
                for b in [-1, 1] as [Float] {
                    points += [[0, a / phi, b * phi], [a / phi, b * phi, 0], [a * phi, 0, b / phi]]
                }
            }
            vertices = points
            circumradius = 6.6
        case .d20:
            var points: [SIMD3<Float>] = []
            for a in [-1, 1] as [Float] {
                for b in [-1, 1] as [Float] {
                    points += [[0, a, b * phi], [a, b * phi, 0], [a * phi, 0, b]]
                }
            }
            vertices = points
            circumradius = 5.6
        }
        let largest = vertices.map(simd_length).max() ?? 1
        return (vertices.map { $0 * circumradius / largest }, circumradius)
    }

    // The faces of the convex hull of `vertices`, each wound counterclockwise seen from outside.
    static func faces(of vertices: [SIMD3<Float>]) -> [[Int]] {
        let center = vertices.reduce(.zero, +) / Float(vertices.count)
        let tolerance: Float = 1e-3 * (vertices.map { simd_length($0 - center) }.max() ?? 1)
        var faces: [[Int]] = []
        var normals: [SIMD3<Float>] = []
        for a in vertices.indices {
            for b in (a + 1)..<vertices.count {
                for c in (b + 1)..<vertices.count {
                    var normal = simd_cross(vertices[b] - vertices[a], vertices[c] - vertices[a])
                    guard simd_length(normal) > 1e-6 else {
                        continue
                    }
                    normal = simd_normalize(normal)
                    if simd_dot(normal, vertices[a] - center) < 0 {
                        normal = -normal
                    }
                    let offset = simd_dot(normal, vertices[a])
                    let distances = vertices.map { simd_dot(normal, $0) - offset }
                    guard distances.allSatisfy({ $0 <= tolerance }), !normals.contains(where: { simd_dot($0, normal) > 0.9999 }) else {
                        continue
                    }
                    let onPlane = vertices.indices.filter { abs(distances[$0]) <= tolerance }
                    let faceCenter = onPlane.map { vertices[$0] }.reduce(.zero, +) / Float(onPlane.count)
                    let reference = simd_normalize(vertices[onPlane[0]] - faceCenter)
                    let side = simd_cross(normal, reference)
                    let ordered = onPlane.sorted { first, second in
                        func angle(_ index: Int) -> Float {
                            let direction = vertices[index] - faceCenter
                            return atan2(simd_dot(direction, side), simd_dot(direction, reference))
                        }
                        return angle(first) < angle(second)
                    }
                    faces.append(ordered)
                    normals.append(normal)
                }
            }
        }
        return faces
    }

    // The largest circle centered at the origin inside the convex polygon `points`.
    private static func inradius(_ points: [SIMD2<Float>]) -> Float {
        let distances = points.indices.map { index in
            let a = points[index], b = points[(index + 1) % points.count]
            let edge = simd_normalize(b - a)
            return abs(a.x * edge.y - a.y * edge.x)
        }
        return distances.min() ?? 1
    }

    // MARK: Numbers

    // Per face: one number, or (for the D4) one number per corner.
    static func labels(_ kind: DiceDemo.Kind, faces: [[Int]], vertices: [SIMD3<Float>]) -> [[String]] {
        if kind == .d4 {
            // Each corner shows its vertex's number, so the top vertex reads the same on every visible face.
            return faces.map { face in face.map { "\($0 + 1)" } }
        }
        // Opposite faces add up to n + 1 (n - 1 for the D10's 0 to 9), as on store-bought dice.
        let normals = faces.map { face -> SIMD3<Float> in
            let points = face.map { vertices[$0] }
            return simd_normalize(points.reduce(.zero, +))
        }
        let count = faces.count
        var values = [Int](repeating: -1, count: count)
        if kind == .d10 {
            // Odd numbers around the top tip (vertex 0), so each opposite face, 9 minus it, is even.
            let top = faces.indices.filter { faces[$0].contains(0) }
            for (offset, index) in top.enumerated() {
                values[index] = 2 * offset + 1
                let opposite = faces.indices.min { simd_dot(normals[$0], normals[index]) < simd_dot(normals[$1], normals[index]) }
                if let opposite {
                    values[opposite] = 9 - values[index]
                }
            }
            return values.map { ["\($0)"] }
        }
        var next = 0
        for index in 0..<count where values[index] < 0 {
            let opposite = (0..<count).filter { values[$0] < 0 && $0 != index }.min { simd_dot(normals[$0], normals[index]) < simd_dot(normals[$1], normals[index]) }
            values[index] = next
            if let opposite {
                values[opposite] = count - 1 - next
            }
            next += 1
        }
        if kind == .d6 {
            // Western dice: 1, 2 and 3 meet at a corner counterclockwise, seen from outside. Swapping 3 and 4 mirrors
            // the layout and keeps opposite faces adding up to 7.
            func normal(_ value: Int) -> SIMD3<Float> { normals[values.firstIndex(of: value) ?? 0] }
            if simd_dot(normal(0), simd_cross(normal(1), normal(2))) < 0 {
                values = values.map { $0 == 2 ? 3 : $0 == 3 ? 2 : $0 }
            }
        }
        return values.map { ["\($0 + 1)"] }
    }

    // The numbers mask and its alpha (for the normal map).
    private static func drawMask(_ kind: DiceDemo.Kind, layouts: [FaceLayout], labels: [[String]]) -> (mask: CGImage, alpha: [Float]) {
        let size = atlasSize
        let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        for (layout, faceLabels) in zip(layouts, labels) {
            if kind == .d4 {
                // Small numbers near each corner, reading toward it.
                for (corner, label) in zip(layout.corners, faceLabels) {
                    let toward = simd_normalize(corner - layout.center)
                    let position = layout.center + toward * layout.inradius * 1.25
                    draw(label, in: context, at: position, height: layout.inradius * 0.62, up: toward)
                }
            } else {
                let label = faceLabels[0]
                let digits = Float(label.count)
                // Each face was laid out with its up direction along the cell's +y.
                draw(label, in: context, at: layout.center, height: layout.inradius * (digits > 1 ? 0.95 : 1.15), up: [0, 1], underline: label == "6" || label == "9")
            }
        }
        let image = context.makeImage()!
        let pixels = context.data!.assumingMemoryBound(to: UInt8.self)
        let alpha = (0..<(size * size)).map { Float(pixels[$0 * 4 + 3]) / 255 }
        return (image, alpha)
    }

    private static func draw(_ text: String, in context: CGContext, at center: SIMD2<Float>, height: Float, up: SIMD2<Float>, underline: Bool = false) {
        let font = CTFontCreateWithName("SF Pro Rounded Bold" as CFString, CGFloat(height), nil)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: CGColor(red: 1, green: 1, blue: 1, alpha: 1)]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        context.saveGState()
        context.translateBy(x: CGFloat(center.x), y: CGFloat(center.y))
        context.rotate(by: CGFloat(atan2(up.y, up.x) - .pi / 2))
        context.textPosition = CGPoint(x: -bounds.midX, y: -bounds.midY)
        CTLineDraw(line, context)
        if underline {
            let barHeight = CGFloat(height) * 0.08
            context.fill(CGRect(x: bounds.minX - bounds.midX, y: -bounds.height / 2 - barHeight * 2.5, width: bounds.width, height: barHeight))
        }
        context.restoreGState()
    }

    // MARK: Normal map

    // The numbers engraved: height falls where the mask is opaque, softened so the walls slope.
    private static func normalMap(height alpha: [Float]) -> CGImage {
        let size = atlasSize
        var height = alpha.map { -$0 }
        for _ in 0..<2 {
            var blurred = height
            for y in 0..<size {
                for x in 0..<size {
                    var sum: Float = 0
                    for dy in -1...1 {
                        for dx in -1...1 {
                            sum += height[min(max(y + dy, 0), size - 1) * size + min(max(x + dx, 0), size - 1)]
                        }
                    }
                    blurred[y * size + x] = sum / 9
                }
            }
            height = blurred
        }
        let strength: Float = 6
        let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4, space: CGColorSpace(name: CGColorSpace.linearSRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        let pixels = context.data!.assumingMemoryBound(to: UInt8.self)
        // `height` is in bitmap memory order (rows top down), like this bitmap, so rows map one to one. Image y runs
        // down, so the slope in y is negated.
        for row in 0..<size {
            let y = row
            for x in 0..<size {
                func at(_ px: Int, _ py: Int) -> Float {
                    height[min(max(py, 0), size - 1) * size + min(max(px, 0), size - 1)]
                }
                let dx = (at(x + 1, y) - at(x - 1, y)) * strength
                let dy = (at(x, y - 1) - at(x, y + 1)) * strength
                let normal = simd_normalize(SIMD3<Float>(-dx, -dy, 1))
                let offset = (row * size + x) * 4
                pixels[offset] = UInt8((normal.x * 0.5 + 0.5) * 255)
                pixels[offset + 1] = UInt8((normal.y * 0.5 + 0.5) * 255)
                pixels[offset + 2] = UInt8((normal.z * 0.5 + 0.5) * 255)
                pixels[offset + 3] = 255
            }
        }
        return context.makeImage()!
    }
}
