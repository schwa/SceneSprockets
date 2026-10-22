import Foundation
import simd
import SwiftMesh

// Spur gears of any size, for the Gears demo and the dice tray's gear mode.
struct GearSpec: Hashable, Sendable {
    var teeth: Int
    // Tooth size: pitch diameter / teeth. Gears with the same module mesh.
    var module: Float = 0.1
    var thickness: Float = 0.2
    // 0 for a solid gear.
    var holeRadius: Float = 0

    var pitchRadius: Float { module * Float(teeth) / 2 }
    var tipRadius: Float { pitchRadius + module }
    var rootRadius: Float { max(pitchRadius - 1.25 * module, holeRadius + module * 0.5) }
}

extension Mesh {
    // A spur gear in the XY plane, centered on the origin, extruded along Z (front face at +thickness / 2). Tooth 0 is
    // centered on +X. Flanks curve like involutes; edges are sharp, flanks smooth.
    static func gear(_ spec: GearSpec, flankSamples: Int = 5) -> Mesh {
        let profile = gearProfile(spec, flankSamples: flankSamples)
        let count = profile.count
        let half = spec.thickness / 2
        let hasHole = spec.holeRadius > 0
        // The profile is star-shaped around the center, so each point pairs with a point on the hole (or the center)
        // at the same angle, and the faces are quads (or triangles) between them.
        let inner: [SIMD2<Float>] = profile.map { point in
            hasHole ? simd_normalize(point) * spec.holeRadius : .zero
        }
        var positions: [SIMD3<Float>] = []
        var faces: [[Int]] = []
        func add(_ points: [SIMD3<Float>]) {
            faces.append(Array(positions.count..<(positions.count + points.count)))
            positions += points
        }
        for index in 0..<count {
            let next = (index + 1) % count
            let a = profile[index], b = profile[next]
            let ia = inner[index], ib = inner[next]
            // Front (+Z) and back, wound counterclockwise seen from outside.
            if hasHole {
                add([[ia.x, ia.y, half], [a.x, a.y, half], [b.x, b.y, half], [ib.x, ib.y, half]])
                add([[ib.x, ib.y, -half], [b.x, b.y, -half], [a.x, a.y, -half], [ia.x, ia.y, -half]])
                // The bore.
                add([[ia.x, ia.y, -half], [ia.x, ia.y, half], [ib.x, ib.y, half], [ib.x, ib.y, -half]])
            } else {
                add([[0, 0, half], [a.x, a.y, half], [b.x, b.y, half]])
                add([[0, 0, -half], [b.x, b.y, -half], [a.x, a.y, -half]])
            }
            // The rim.
            add([[a.x, a.y, half], [a.x, a.y, -half], [b.x, b.y, -half], [b.x, b.y, half]])
        }
        var mesh = Mesh(positions: positions, faces: faces).withSmoothNormals(creaseAngle: .pi / 5)
        // Planar coordinates over the gear's disc.
        let extent = spec.tipRadius * 2
        mesh.textureCoordinates = mesh.topology.halfEdges.map { halfEdge in
            let position = positions[halfEdge.origin.raw]
            return SIMD2(position.x / extent + 0.5, 0.5 - position.y / extent)
        }
        return mesh
    }

    // The outline, counterclockwise: for each tooth, the root gap, a rising flank, the tip, a falling flank.
    private static func gearProfile(_ spec: GearSpec, flankSamples: Int) -> [SIMD2<Float>] {
        let pitch = 2 * Float.pi / Float(spec.teeth)
        // Half the tooth's angular width at the root, the pitch circle and the tip.
        let halfRoot = pitch * 0.30, halfPitch = pitch * 0.25, halfTip = pitch * 0.13
        func point(_ angle: Float, _ radius: Float) -> SIMD2<Float> {
            [cos(angle) * radius, sin(angle) * radius]
        }
        // Half width at radius `r`, through the pitch circle: an involute-like curve, wide at the root.
        func halfWidth(_ r: Float) -> Float {
            if r <= spec.pitchRadius {
                let t = (r - spec.rootRadius) / max(spec.pitchRadius - spec.rootRadius, 1e-4)
                return simd_mix(halfRoot, halfPitch, pow(max(t, 0), 0.7))
            }
            let t = (r - spec.pitchRadius) / max(spec.tipRadius - spec.pitchRadius, 1e-4)
            return simd_mix(halfPitch, halfTip, pow(t, 1.3))
        }
        var points: [SIMD2<Float>] = []
        for tooth in 0..<spec.teeth {
            let center = Float(tooth) * pitch
            // The root gap before this tooth, from the previous tooth's root edge.
            points.append(point(center - pitch / 2, spec.rootRadius))
            for sample in 0...flankSamples {
                let r = simd_mix(spec.rootRadius, spec.tipRadius, Float(sample) / Float(flankSamples))
                points.append(point(center - halfWidth(r), r))
            }
            for sample in (0...flankSamples).reversed() {
                let r = simd_mix(spec.rootRadius, spec.tipRadius, Float(sample) / Float(flankSamples))
                points.append(point(center + halfWidth(r), r))
            }
        }
        return points
    }
}

// Meshing two gears with the same module: where the second sits, and its angle for a given angle of the first.
enum GearTrain {
    // `direction` is the angle from the first gear's center to the second's.
    static func center(of second: GearSpec, meshingWith first: GearSpec, at firstCenter: SIMD2<Float>, direction: Float) -> SIMD2<Float> {
        firstCenter + SIMD2(cos(direction), sin(direction)) * (first.pitchRadius + second.pitchRadius)
    }

    // The second gear's angle when the first is at `firstAngle`, so a tooth always meets a gap on the line between
    // the centers. Tooth phases (in teeth) of the two gears at the contact point always add up to one half.
    static func angle(of second: GearSpec, meshingWith first: GearSpec, firstAngle: Float, direction: Float) -> Float {
        let firstPhase = Float(first.teeth) * (direction - firstAngle) / (2 * .pi)
        return direction + .pi - (2 * .pi / Float(second.teeth)) * (0.5 - firstPhase)
    }
}
