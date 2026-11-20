import Foundation
import MetalSprockets
import MetalSprocketsPBRShaders

// One `PBRMaterialResources` element per batch of a model (`Batch.element`): the uniforms and textures the batch was
// last drawn with.
// A draw writes only what changed since then, and ArgumentBuffer patches only those fields into the next version.
// Encoded draws keep the version they were bound with, so writes never race the GPU.
// Owned by one renderer: renderers of the same model with different poses or overrides must not share one.
final class PBRMaterialTable {
    private struct Entry {
        var material: ObjectIdentifier
        var uniforms: PBRMaterialUniforms
        // Written from animated values, so the next frame must compare again even if it is not animated.
        var isAnimated: Bool
    }

    let model: PBRModel
    let resources: ArgumentBuffer
    private var entries: [Entry?]

    init(model: PBRModel) {
        self.model = model
        let count = model.opaqueBatches.count + model.blendedBatches.count
        resources = ArgumentBuffer(device: model.device, count: max(count, 1), label: "PBR Materials")
        entries = Array(repeating: nil, count: count)
    }

    // Writes the fields of the draw's batch element that differ from what it held. A batch's uniforms depend only on its
    // material, its primitive (fixed per element) and the pose's animated values, so an unanimated element whose material
    // did not change needs no work.
    func write(_ draw: PBRRenderer.BatchDraw) {
        let index = draw.batch.element
        let identifier = ObjectIdentifier(draw.material)
        let old = entries[index]
        if let old, old.material == identifier, !old.isAnimated, !draw.isAnimated {
            return
        }
        if old?.material != identifier {
            resources.setMaterialResources(draw.material.textureBindings, element: index)
        }
        let uniforms = draw.uniforms
        if old.map({ !bitwiseEqual($0.uniforms, uniforms) }) ?? true {
            resources.set("uniforms", value: uniforms, element: index)
        }
        entries[index] = Entry(material: identifier, uniforms: uniforms, isAnimated: draw.isAnimated)
    }
}

// Holds a renderer's table across frames; a new model gets a new table.
final class PBRMaterialTableCache {
    private var table: PBRMaterialTable?

    func table(for model: PBRModel) -> PBRMaterialTable {
        if let table, table.model === model {
            return table
        }
        let table = PBRMaterialTable(model: model)
        self.table = table
        return table
    }
}

private func bitwiseEqual<T>(_ lhs: T, _ rhs: T) -> Bool {
    withUnsafePointer(to: lhs) { lhsPointer in
        withUnsafePointer(to: rhs) { rhsPointer in
            memcmp(lhsPointer, rhsPointer, MemoryLayout<T>.size) == 0
        }
    }
}
