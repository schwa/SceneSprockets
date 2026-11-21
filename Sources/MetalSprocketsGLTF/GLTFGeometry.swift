import Foundation
import Metal
import MetalSprocketsPBR
import MetalSprocketsPBRShaders
import MetalSupport
import simd
import SwiftGLTF
import SwiftMesh

enum GLTFGeometry {
    /// A glTF primitive's vertex attributes and index list, for ``PBRGeometryBuilder``.
    struct Primitive {
        var attributes: [MetalMesh.VertexAttributeData]
        var indices: [UInt32]
        var primitiveType: MTLPrimitiveType
        var morphTargets: MetalMesh.MorphTargets?
    }

    /// A glTF primitive's data. Strips, fans and loops become lists; normal-mapped primitives without tangents get
    /// MikkTSpace tangents. Nil when nothing would be drawn.
    /// `defaultWeights` are the mesh's morph weights (glTF mesh.weights); used when they match the targets.
    static func makePrimitive(_ primitive: SwiftGLTF.Mesh.Primitive, container: Container, defaultWeights: [Float]) throws -> Primitive? {
        let document = container.document
        // Every attribute must have one value per vertex, with one of `components` components.
        var vertexCount = 0
        func floats(_ semantic: SwiftGLTF.Mesh.Primitive.Semantic, components: Set<Int>) throws -> (values: [Float], components: Int)? {
            guard let index = primitive.attributes[semantic] else {
                return nil
            }
            let accessor = try index.resolve(in: document)
            let componentCount = accessor.type.componentCount
            guard components.contains(componentCount) else {
                throw GLTFError.invalidDocument("\(semantic.rawValue) has \(accessor.type) values")
            }
            let values = try container.checkedFloatComponents(for: accessor)
            guard values.count == vertexCount * componentCount else {
                throw GLTFError.invalidDocument("\(semantic.rawValue) has \(values.count / componentCount) values for \(vertexCount) vertices")
            }
            return (values, componentCount)
        }

        guard let positionIndex = primitive.attributes[.POSITION] else {
            throw PBRGeometryError.missingPositions
        }
        vertexCount = try positionIndex.resolve(in: document).count
        guard let positions = try floats(.POSITION, components: [3]) else {
            throw PBRGeometryError.missingPositions
        }
        // swiftlint:disable:next discouraged_optional_collection - nil means absent or not overridden, which differs from empty
        func vectors2(_ data: (values: [Float], components: Int)?) -> [SIMD2<Float>]? {
            data.map { data in (0 ..< vertexCount).map { SIMD2(data.values[$0 * data.components], data.values[$0 * data.components + 1]) } }
        }
        func vectors3(_ values: [Float]) -> [SIMD3<Float>] {
            (0 ..< vertexCount).map { SIMD3(values[$0 * 3], values[$0 * 3 + 1], values[$0 * 3 + 2]) }
        }
        // swiftlint:disable:next discouraged_optional_collection - nil means absent or not overridden, which differs from empty
        func vectors4(_ data: (values: [Float], components: Int)?) -> [SIMD4<Float>]? {
            data.map { data in
                (0 ..< vertexCount).map { index in
                    let base = index * data.components
                    return data.components == 4
                        ? SIMD4(data.values[base], data.values[base + 1], data.values[base + 2], data.values[base + 3])
                        : SIMD4(data.values[base], data.values[base + 1], data.values[base + 2], 1)
                }
            }
        }
        var positionValues = vectors3(positions.values)
        var normals = try floats(.NORMAL, components: [3]).map { vectors3($0.values) }
        var tangents = try vectors4(floats(.TANGENT, components: [4]))
        // Only VEC2 is valid; extra components are ignored.
        var texCoords0 = try vectors2(floats(.TEXCOORD_0, components: [2, 3, 4]))
        var texCoords1 = try vectors2(floats(.TEXCOORD_1, components: [2, 3, 4]))
        var colors = try vectors4(floats(.COLOR_0, components: [3, 4]))
        // Missing attributes in a target contribute nothing.
        var morphTargets: [MetalMesh.MorphTargets.Target] = try primitive.targets.map { target in
            // swiftlint:disable:next discouraged_optional_collection - nil means absent or not overridden, which differs from empty
            func offsets(_ semantic: SwiftGLTF.Mesh.Primitive.Semantic) throws -> [SIMD3<Float>]? {
                guard let index = target[semantic] else {
                    return nil
                }
                let values = try container.checkedFloatComponents(for: index.resolve(in: document))
                guard values.count == vertexCount * 3 else {
                    throw GLTFError.invalidDocument("Morph target \(semantic.rawValue) count mismatch")
                }
                return vectors3(values)
            }
            return MetalMesh.MorphTargets.Target(positionOffsets: try offsets(.POSITION), normalOffsets: try offsets(.NORMAL), tangentOffsets: try offsets(.TANGENT))
        }
        // swiftlint:disable:next discouraged_optional_collection - nil means absent or not overridden, which differs from empty
        var joints: [SIMD4<UInt16>]?
        // swiftlint:disable:next discouraged_optional_collection - nil means absent or not overridden, which differs from empty
        var weights: [SIMD4<Float>]?
        if let jointData = try floats(.JOINTS_0, components: [1, 2, 3, 4]), let weightData = try floats(.WEIGHTS_0, components: [1, 2, 3, 4]), jointData.components == 4, weightData.components == 4 {
            // Clamped first: the conversion traps on NaN and on values outside UInt16.
            joints = vectors4(jointData)?.map { joint in
                let finite = joint.replacing(with: 0, where: .!(joint .== joint))
                return SIMD4<UInt16>(finite.clamped(lowerBound: .zero, upperBound: SIMD4(repeating: 65_535)), rounding: .toNearestOrEven)
            }
            weights = vectors4(weightData)
        }

        var indices: [UInt32]
        if let indicesIndex = primitive.indices {
            let indicesAccessor = try indicesIndex.resolve(in: document)
            indices = try readIndices(container.checkedData(for: indicesAccessor), componentType: indicesAccessor.componentType)
            if let bad = indices.first(where: { Int($0) >= vertexCount }) {
                throw GLTFError.invalidDocument("Index \(bad) is out of range for \(vertexCount) vertices")
            }
        } else {
            indices = (0 ..< UInt32(vertexCount)).map(\.self)
        }

        let primitiveType: MTLPrimitiveType
        switch primitive.mode {
        case .TRIANGLES:
            primitiveType = .triangle
            indices.removeLast(indices.count % 3)

        case .TRIANGLE_STRIP:
            primitiveType = .triangle
            indices = triangleList(fromStrip: indices)

        case .TRIANGLE_FAN:
            primitiveType = .triangle
            indices = triangleList(fromFan: indices)

        case .POINTS:
            primitiveType = .point

        case .LINES:
            primitiveType = .line
            indices.removeLast(indices.count % 2)

        case .LINE_STRIP:
            primitiveType = .line
            indices = lineList(fromStrip: indices, closed: false)

        case .LINE_LOOP:
            primitiveType = .line
            indices = lineList(fromStrip: indices, closed: true)
        }
        guard !indices.isEmpty else {
            return nil
        }

        // glTF requires flat normals when NORMAL is missing. The fragment shader derives them per pixel (hasNormals), so
        // vertices stay shared instead of being unwelded per triangle.

        // Normal-mapped primitives without TANGENT get MikkTSpace tangents, the space their normal maps are baked in.
        // Vertices are split where adjacent triangles need different tangents (UV seams, mirrored UVs).
        var hasTangents = tangents != nil
        let materialIndices = [primitive.material?.index].compactMap(\.self) + primitive.variantMaterials.values
        let normalMapTexCoord = materialIndices.lazy.compactMap { index in
            document.materials.indices.contains(index) ? document.materials[index].normalTexture?.texCoord : nil
        }.first
        if !hasTangents, let normalValues = normals, primitiveType == .triangle, let normalMapTexCoord {
            let texCoords = (normalMapTexCoord == 1 ? texCoords1 : texCoords0) ?? Array(repeating: .zero, count: vertexCount)
            let cornerTangents = GLTFTangents.cornerTangents(
                positions: positionValues,
                normals: normalValues,
                // glTF's v runs down the image; MikkTSpace (as in Blender, where maps are baked) expects v up.
                texCoords: texCoords.map { SIMD2($0.x, 1 - $0.y) },
                indices: indices
            )
            let welded = GLTFTangents.weld(cornerTangents: cornerTangents, indices: indices)
            // swiftlint:disable:next discouraged_optional_collection - nil means absent or not overridden, which differs from empty
            func remap<T>(_ values: [T]?) -> [T]? {
                values.map { values in welded.sources.map { values[$0] } }
            }
            // swiftlint:disable:next force_unwrapping - remap returns nil only for nil input, and positions always exist
            positionValues = remap(positionValues)!
            normals = remap(normals)
            texCoords0 = remap(texCoords0)
            texCoords1 = remap(texCoords1)
            colors = remap(colors)
            joints = remap(joints)
            weights = remap(weights)
            morphTargets = morphTargets.map { target in
                MetalMesh.MorphTargets.Target(positionOffsets: remap(target.positionOffsets), normalOffsets: remap(target.normalOffsets), tangentOffsets: remap(target.tangentOffsets))
            }
            tangents = welded.tangents
            indices = welded.indices
            hasTangents = true
        }

        var attributes: [MetalMesh.VertexAttributeData] = [.positions(positionValues)]
        if let normals {
            attributes.append(.normals(normals))
        }
        if let tangents {
            attributes.append(.tangents(tangents))
        }
        if let texCoords0 {
            attributes.append(.textureCoordinates(texCoords0, set: 0))
        }
        if let texCoords1 {
            attributes.append(.textureCoordinates(texCoords1, set: 1))
        }
        if let colors {
            attributes.append(.colors(colors))
        }
        if let joints, let weights {
            attributes.append(.jointIndices(joints))
            attributes.append(.jointWeights(weights))
        }
        return Primitive(
            attributes: attributes,
            indices: indices,
            primitiveType: primitiveType,
            morphTargets: morphTargets.isEmpty ? nil : MetalMesh.MorphTargets(targets: morphTargets, defaultWeights: defaultWeights.count == morphTargets.count ? defaultWeights : [])
        )
    }

    static func readIndices(_ data: Data, componentType: Accessor.ComponentType) -> [UInt32] {
        data.withUnsafeBytes { raw in
            switch componentType {
            case .UNSIGNED_BYTE:
                return raw.map { UInt32($0) }

            case .UNSIGNED_SHORT:
                return (0 ..< raw.count / 2).map { UInt32(raw.loadUnaligned(fromByteOffset: $0 * 2, as: UInt16.self)) }

            default:
                return (0 ..< raw.count / 4).map { raw.loadUnaligned(fromByteOffset: $0 * 4, as: UInt32.self) }
            }
        }
    }

    /// Consecutive pairs of a line strip, plus the closing segment for a loop.
    static func lineList(fromStrip strip: [UInt32], closed: Bool) -> [UInt32] {
        guard strip.count >= 2 else {
            return []
        }
        var lines = zip(strip, strip.dropFirst()).flatMap { [$0, $1] }
        if closed, strip.count > 2, let first = strip.first, let last = strip.last {
            lines += [last, first]
        }
        return lines
    }

    static func triangleList(fromStrip strip: [UInt32]) -> [UInt32] {
        guard strip.count >= 3 else {
            return []
        }
        var result: [UInt32] = []
        for index in 0 ..< strip.count - 2 {
            if index.isMultiple(of: 2) {
                result += [strip[index], strip[index + 1], strip[index + 2]]
            } else {
                result += [strip[index + 1], strip[index], strip[index + 2]]
            }
        }
        return result
    }

    static func triangleList(fromFan fan: [UInt32]) -> [UInt32] {
        guard fan.count >= 3 else {
            return []
        }
        return (1 ..< fan.count - 1).flatMap { [fan[0], fan[$0], fan[$0 + 1]] }
    }
}
