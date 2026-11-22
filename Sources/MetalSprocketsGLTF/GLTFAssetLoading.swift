import Metal
import MetalSprockets
import MetalSprocketsPBR
import MetalSprocketsPBRShaders
import simd
import SwiftGLTF

// The stages GLTFAsset is built from: load the file's resources (geometry through PBRGeometryBuilder), then flatten
// one scene into a PBRModel through PBRModelBuilder.

extension GLTFAsset.Resources {
    /// Loads everything that does not depend on the scene or variant: textures and materials, meshes, skins and
    /// animations, with warnings for what was skipped.
    ///
    /// Each step is its own function, so it can be tested alone (#562): required extensions, materials, geometry,
    /// skins, animations, then each ``GLTFExtensionFeature``'s load step.
    static func load(container: Container, device: MTLDevice, options: GLTFLoadOptions = GLTFLoadOptions()) throws -> Self {
        var warnings = try checkRequiredExtensions(container.document, options: options)
        let textures = GLTFTextureCache(container: container, device: device, decoders: options.textureDecoders)
        let (materials, defaultMaterial) = loadMaterials(container.document, textures: textures)
        let geometry = try loadGeometry(container, device: device)
        warnings += geometry.warnings
        let skins = try loadSkins(container)
        let (animations, animationWarnings) = GLTFAnimationClip.load(container: container)
        warnings += animationWarnings
        var resources = Self(device: device, materials: materials, defaultMaterial: defaultMaterial, meshes: geometry.meshes, primitiveMaterials: geometry.primitiveMaterials, skins: skins, animations: animations, warnings: [])
        for feature in GLTFExtensionFeature.all {
            try feature.load?(container, &resources, &warnings)
        }
        // Texture warnings last: textures load lazily, so all materials have asked for theirs by now.
        resources.warnings = warnings + textures.warnings
        return resources
    }

    /// A warning when the file requires extensions `options` does not support and loads them anyway; throws when it
    /// should not load them.
    static func checkRequiredExtensions(_ document: Document, options: GLTFLoadOptions) throws -> [GLTFWarning] {
        let unsupported = Set(document.extensionsRequired).subtracting(options.supportedExtensions).sorted()
        guard !unsupported.isEmpty else {
            return []
        }
        guard options.loadsUnsupportedRequiredExtensions else {
            throw GLTFUnsupportedExtensionsError(extensions: unsupported)
        }
        return [GLTFWarning(.requiredExtensionsLoadedAnyway(unsupported), "Required extensions not supported, loaded anyway: \(unsupported.joined(separator: ", "))")]
    }

    /// Every material, and the default material for primitives without one.
    static func loadMaterials(_ document: Document, textures: GLTFTextureCache) -> (materials: [PBRMaterial], defaultMaterial: PBRMaterial) {
        textures.preload(document.materials)
        let defaultMaterial = PBRMaterial(material: nil, textures: textures)
        return (document.materials.map { PBRMaterial(material: $0, textures: textures) }, defaultMaterial)
    }

    /// Every mesh's primitives in one set of shared buffers, with each primitive's material and variant material
    /// indices. Primitives that cannot be built are left out with a warning.
    static func loadGeometry(_ container: Container, device: MTLDevice) throws -> (meshes: [[GLTFAsset.Primitive]], primitiveMaterials: [GLTFAsset.Primitive.Key: (material: Int, variants: [Int: Int])], warnings: [GLTFWarning]) {
        var warnings: [GLTFWarning] = []
        var geometry = PBRGeometryBuilder(device: device)
        var meshPrimitiveIndices: [[Int]] = []
        var materialIndices: [Int: (material: Int, variants: [Int: Int])] = [:]
        for (meshIndex, mesh) in container.document.meshes.enumerated() {
            var indices: [Int] = []
            for (primitiveIndex, primitive) in mesh.primitives.enumerated() {
                let label = mesh.name ?? "mesh\(meshIndex)"
                do {
                    if let data = try GLTFGeometry.makePrimitive(primitive, container: container, defaultWeights: mesh.weights) {
                        let index = try geometry.add(attributes: data.attributes, indices: data.indices, primitiveType: data.primitiveType, morphTargets: data.morphTargets, label: "\(label)[\(primitiveIndex)]")
                        materialIndices[index] = (primitive.material?.index ?? -1, primitive.variantMaterials)
                        indices.append(index)
                    } else {
                        warnings.append(GLTFWarning(.primitiveSkipped(mesh: label, primitive: primitiveIndex), "Skipped \(label)[\(primitiveIndex)]: unsupported mode \(primitive.mode)"))
                    }
                } catch {
                    warnings.append(GLTFWarning(.primitiveSkipped(mesh: label, primitive: primitiveIndex), "Skipped \(label)[\(primitiveIndex)]: \(error)"))
                }
            }
            meshPrimitiveIndices.append(indices)
        }
        let primitives = try geometry.build()
        let meshes = meshPrimitiveIndices.map { $0.map { primitives[$0] } }
        let primitiveMaterials = Dictionary(uniqueKeysWithValues: materialIndices.map { (primitives[$0.key].key, $0.value) })
        return (meshes, primitiveMaterials, warnings)
    }

    /// Every skin, with its inverse bind matrices checked.
    static func loadSkins(_ container: Container) throws -> [PBRModel.Skin] {
        try container.document.skins.map { skin in
            PBRModel.Skin(joints: skin.joints.map(\.index), inverseBindMatrices: try container.checkedInverseBindMatrices(for: skin))
        }
    }
}

extension Container {
    /// One inverse bind matrix per joint (identity when the skin has none). Throws unless the accessor holds a MAT4
    /// for every joint.
    func checkedInverseBindMatrices(for skin: Skin) throws -> [simd_float4x4] {
        guard let index = skin.inverseBindMatrices else {
            return Array(repeating: matrix_identity_float4x4, count: skin.joints.count)
        }
        let accessor = try index.resolve(in: document)
        guard accessor.type == .MAT4, accessor.count >= skin.joints.count else {
            throw GLTFError.invalidDocument("Skin inverseBindMatrices must be a MAT4 for each of its \(skin.joints.count) joints")
        }
        let floats = try checkedFloatComponents(for: accessor)
        return (0 ..< skin.joints.count).map { joint in
            floats.withUnsafeBufferPointer { floats in
                let base = joint * 16
                return simd_float4x4(
                    SIMD4(floats[base], floats[base + 1], floats[base + 2], floats[base + 3]),
                    SIMD4(floats[base + 4], floats[base + 5], floats[base + 6], floats[base + 7]),
                    SIMD4(floats[base + 8], floats[base + 9], floats[base + 10], floats[base + 11]),
                    SIMD4(floats[base + 12], floats[base + 13], floats[base + 14], floats[base + 15])
                )
            }
        }
    }
}

/// One scene of a document, flattened into a ``PBRModel``, with the poser that animates it.
struct GLTFSceneContents {
    var model: PBRModel
    var poser: GLTFPoser

    /// Walks scene `sceneIndex` (or every root node when the document has no scenes). Hidden nodes
    /// (KHR_node_visibility) contribute no instances or lights, unless an animation can show them: then they are
    /// loaded and the rest pose hides them. `variant` picks KHR_materials_variants materials.
    /// Throws for out-of-range nodes and cyclic hierarchies.
    init(document: Document, resources: GLTFAsset.Resources, sceneIndex: Int, variant: Int?) throws {
        let animatesVisibility = resources.animations.contains { clip in
            clip.channels.contains {
                if case .visibility = $0.target {
                    true
                } else {
                    false
                }
            }
        }
        let hierarchy = try GLTFNodeHierarchy(document: document, sceneIndex: sceneIndex)
        let materials = resources.materials.map { GLTFPoser.Material(id: ObjectIdentifier($0), rest: $0.animatedState()) }
        let poser = try GLTFPoser(document: document, hierarchy: hierarchy, animations: resources.animations, materials: materials)
        var builder = PBRModelBuilder(device: resources.device, restPose: poser.restPose)
        builder.skins = resources.skins
        // Everything loaded stays resident, so other scenes and variants of the same file reuse it.
        builder.residentMaterials = resources.materials + [resources.defaultMaterial]
        builder.residentPrimitives = resources.meshes.flatMap(\.self)

        // `visible` is false under a node hidden by KHR_node_visibility; its meshes and its descendants' are skipped.
        hierarchy.walk(hierarchy.rest) { nodeIndex, world, visible in
            let node = document.nodes[nodeIndex]
            if visible || animatesVisibility, let meshIndex = node.mesh?.index, resources.meshes.indices.contains(meshIndex) {
                for primitive in resources.meshes[meshIndex] {
                    let material = resources.material(for: primitive, variant: variant)
                    // Only primitives with joint data can be skinned; others ignore the node's skin.
                    let skinIndex = !primitive.isSkinned ? nil : node.skin.map(\.index).flatMap { document.skins.indices.contains($0) ? $0 : nil }
                    // EXT_mesh_gpu_instancing copies; skinned meshes follow their joints, so they are drawn once.
                    let instanceMatrices = skinIndex == nil ? resources.nodeInstanceMatrices[nodeIndex] ?? [matrix_identity_float4x4] : [matrix_identity_float4x4]
                    for instanceMatrix in instanceMatrices {
                        builder.addInstance(primitive, material: material, node: nodeIndex, instanceMatrix: instanceMatrix, worldMatrix: world * instanceMatrix, skin: skinIndex)
                    }
                }
            }
        }
        // Hidden lights do not shine at rest.
        builder.lights = poser.lights(pose: poser.restPose)
        self.model = try builder.build()
        self.poser = poser
    }
}
