import Foundation
import MetalSprockets
import MetalSprocketsPBRShaders

// One `PBRMaterialResources` element per batch of a model: the uniforms and textures the batch was last drawn with.
// A draw writes only what changed since then, and ArgumentBuffer patches only those fields into the next version.
// Encoded draws keep the version they were bound with, so writes never race the GPU.
// Owned by one renderer: renderers of the same model with different poses or overrides must not share one.
final class PBRMaterialTable {
    private struct Entry {
        var material: ObjectIdentifier
        var uniforms: PBRMaterialUniforms
    }

    let model: PBRModel
    let resources: ArgumentBuffer
    private var entries: [Entry?]
    // Merged sets whose records hold their rest materials, with nothing animated or overridden. They need no writes
    // until a pose or override applies, or a per-batch draw changes one of their elements.
    private var setsAtRest: Set<ObjectIdentifier> = []

    init(model: PBRModel) {
        self.model = model
        let count = model.opaqueBatches.count + model.blendedBatches.count
        resources = ArgumentBuffer(device: model.device, count: max(count, 1), label: "PBR Materials")
        entries = Array(repeating: nil, count: count)
    }

    // Batch IDs are indices into the model's opaque or blended batches; blended batches follow the opaque ones.
    func index(of batch: PBRModel.Batch) -> Int {
        batch.material.isBlended ? model.opaqueBatches.count + batch.id : batch.id
    }

    // The batch's element, after writing whatever differs from what it held.
    func write(_ draw: PBRDrawPlan.BatchDraw) -> UInt32 {
        let index = index(of: draw.batch)
        if write(element: index, material: draw.material, uniforms: draw.uniforms) {
            setsAtRest.removeAll()
        }
        return UInt32(index)
    }

    // The elements of every record of `merged` (opaque, so a record's element is its batch ID).
    func write(_ merged: PBRMergedGeometry, pose: PBRPose?, overrides: PBRModel.MaterialOverrides) {
        let atRest = pose?.materialUniforms.isEmpty != false && !merged.isOverridden(by: overrides)
        let set = ObjectIdentifier(merged)
        if atRest, setsAtRest.contains(set) {
            return
        }
        for record in merged.records {
            _ = write(element: record.batchID, material: merged.material(of: record, overrides: overrides), uniforms: merged.uniforms(of: record, pose: pose, overrides: overrides))
        }
        if atRest {
            setsAtRest.insert(set)
        } else {
            setsAtRest.remove(set)
        }
    }

    // Writes only the fields that differ; returns whether any did.
    private func write(element index: Int, material: PBRMaterial, uniforms: PBRMaterialUniforms) -> Bool {
        let identifier = ObjectIdentifier(material)
        let old = entries[index]
        var changed = false
        if old?.material != identifier {
            resources.setMaterialResources(material.textureBindings, element: index)
            changed = true
        }
        if old.map({ !bitwiseEqual($0.uniforms, uniforms) }) ?? true {
            resources.set("uniforms", value: uniforms, element: index)
            changed = true
        }
        entries[index] = Entry(material: identifier, uniforms: uniforms)
        return changed
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
