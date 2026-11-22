import simd
import SwiftGLTF

/// Everything this package does with one non-material glTF extension at load time, like ``GLTFMaterialFeature`` for
/// material extensions (#562).
///
/// ``all`` is the single list: ``GLTFAsset/builtInExtensions`` comes from it, and ``GLTFAsset/Resources/load`` runs
/// each entry's ``load`` step after the core resources. Extensions that only change how a scene is flattened
/// (KHR_node_visibility, KHR_materials_variants) or how animations are read (KHR_animation_pointer) have no load step;
/// their names are listed here so they are supported, and their work stays where it happens.
struct GLTFExtensionFeature: Sendable {
    var extensionName: String
    /// Reads what the extension adds into `resources`, adding warnings for what it skips. Nil when there is nothing to
    /// load.
    var load: (@Sendable (Container, inout GLTFAsset.Resources, inout [GLTFWarning]) throws -> Void)?

    static let all: [Self] = [
        // Node-relative matrices of each copy of a node's mesh.
        Self(extensionName: EXTMeshGPUInstancing.extensionName) { container, resources, _ in
            resources.nodeInstanceMatrices = try loadInstanceMatrices(container)
        },
        // Each image-based light a scene uses; a broken one is skipped with a warning.
        Self(extensionName: EXTLightsImageBased.extensionName) { container, resources, warnings in
            resources.imageBasedLights = loadImageBasedLights(container, warnings: &warnings)
        },
        // Hidden nodes are left out when a scene is flattened (GLTFSceneContents).
        Self(extensionName: KHRNodeVisibility.extensionName, load: nil),
        // Variant materials are recorded per primitive while geometry is built and picked when a scene is flattened.
        Self(extensionName: KHRMaterialsVariants.extensionName, load: nil),
        // Pointer targets are parsed with the animations (GLTFAnimationClip).
        Self(extensionName: "KHR_animation_pointer", load: nil),
        // Metadata only; nothing to render.
        Self(extensionName: "KHR_xmp_json_ld", load: nil)
    ]

    static let extensionNames: Set<String> = Set(all.map(\.extensionName))

    static func loadInstanceMatrices(_ container: Container) throws -> [Int: [simd_float4x4]] {
        var matrices: [Int: [simd_float4x4]] = [:]
        for (index, node) in container.document.nodes.enumerated() where node.mesh != nil {
            matrices[index] = try container.instanceMatrices(for: node)
        }
        return matrices
    }

    static func loadImageBasedLights(_ container: Container, warnings: inout [GLTFWarning]) -> [Int: GLTFImageBasedLight] {
        let document = container.document
        var lights: [Int: GLTFImageBasedLight] = [:]
        for index in Set(document.scenes.indices.compactMap { GLTFImageBasedLight.lightIndex(document: document, sceneIndex: $0) }).sorted() {
            do {
                lights[index] = try GLTFImageBasedLight(container: container, index: index)
            } catch {
                warnings.append(GLTFWarning(.imageBasedLightSkipped(index: index), "Image-based light \(index) skipped: \(error)"))
            }
        }
        return lights
    }
}
