@testable import SceneSprocketsDemoSupport
import simd
import Testing

// #149: the dice use the layouts of store-bought dice.
private struct Numbered {
    var normals: [SIMD3<Float>]
    var values: [Int]
    var faces: [[Int]]

    init(_ kind: DiceDemo.Kind) {
        let vertices = DiceGeometry.solid(kind).vertices
        faces = DiceGeometry.faces(of: vertices)
        normals = faces.map { face in simd_normalize(face.map { vertices[$0] }.reduce(.zero, +)) }
        values = DiceGeometry.labels(kind, faces: faces, vertices: vertices).map { Int($0[0])! }
    }

    func normal(of value: Int) -> SIMD3<Float> {
        normals[values.firstIndex(of: value)!]
    }

    // The value on the face most nearly opposite the face showing `value`.
    func opposite(of value: Int) -> Int {
        let normal = normal(of: value)
        return values[normals.indices.min { simd_dot(normals[$0], normal) < simd_dot(normals[$1], normal) }!]
    }
}

@Test(arguments: [(DiceDemo.Kind.d6, 7), (.d8, 9), (.d10, 9), (.d12, 13), (.d20, 21)])
func oppositeFacesAddUp(kind: DiceDemo.Kind, sum: Int) {
    let die = Numbered(kind)
    for value in die.values {
        #expect(value + die.opposite(of: value) == sum, "\(kind): \(value)")
    }
}

// #148: every edge and corner is beveled, and the bevel stays inside the solid.
@Test(arguments: DiceDemo.Kind.allCases)
func diceHaveBeveledEdgesAndCorners(kind: DiceDemo.Kind) {
    let solid = DiceGeometry.solid(kind)
    let faces = DiceGeometry.faces(of: solid.vertices)
    let edges = faces.map(\.count).reduce(0, +) / 2
    let mesh = DiceGeometry(kind).mesh
    #expect(mesh.topology.faces.count == faces.count + edges + solid.vertices.count)
    let farthest = mesh.positions.map(simd_length).max() ?? 0
    #expect(farthest < solid.circumradius)
}

// Western D6: 1, 2 and 3 meet at a corner in counterclockwise order, seen from outside.
@Test
func sixSidedDieIsCounterclockwise() {
    let die = Numbered(.d6)
    #expect(simd_dot(die.normal(of: 1), simd_cross(die.normal(of: 2), die.normal(of: 3))) > 0)
}

// D10: the odd numbers surround one tip and the even numbers the other.
@Test
func tenSidedDieHasOddAndEvenHalves() {
    let die = Numbered(.d10)
    // Vertex 0 is the top tip.
    let top = die.faces.indices.filter { die.faces[$0].contains(0) }.map { die.values[$0] }
    #expect(top.count == 5)
    #expect(top.allSatisfy { !$0.isMultiple(of: 2) }, "\(top)")
}
