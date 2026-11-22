import GeometryLite3D
import SceneSprockets
import SceneSprocketsBlinnPhong
import simd
import SwiftUI

// Form sections describing one node; embed inside a Form.
struct NodeInspectorView: View {
    var node: SceneGraph.Node

    var body: some View {
        GeneralSectionView(node: node)
        TransformSectionView(transform: node.transform.matrix)
        switch node.content {
        case .empty:
            EmptyView()
        case .light(let light):
            LightSectionView(light: light)
        case .camera:
            Section("Camera") {
                LabeledContent("Projection", value: "Perspective")
            }
        case let .mesh(_, materials, castsShadow, receivesShadow):
            MeshSectionView(materials: materials, castsShadow: castsShadow, receivesShadow: receivesShadow)
        case let .instancedMesh(_, materials, transforms, castsShadow, receivesShadow):
            Section("Instances") {
                LabeledContent("Count", value: transforms.count, format: .number)
            }
            MeshSectionView(materials: materials, castsShadow: castsShadow, receivesShadow: receivesShadow)
        }
    }
}

private struct GeneralSectionView: View {
    var node: SceneGraph.Node

    var body: some View {
        Section("General") {
            LabeledContent("Label", value: node.label ?? "—")
            LabeledContent("Type", value: contentTypeName)
        }
    }

    private var contentTypeName: String {
        switch node.content {
        case .empty: "Empty"
        case .mesh: "Mesh"
        case .instancedMesh: "Instanced Mesh"
        case .light: "Light"
        case .camera: "Camera"
        }
    }
}

private struct TransformSectionView: View {
    var transform: simd_float4x4

    var body: some View {
        Section("Transform") {
            VectorRowView(label: "Position", value: transform.columns.3.xyz)
            VectorRowView(label: "X Axis", value: transform.columns.0.xyz)
            VectorRowView(label: "Y Axis", value: transform.columns.1.xyz)
            VectorRowView(label: "Z Axis", value: transform.columns.2.xyz)
        }
    }
}

private struct LightSectionView: View {
    var light: Light

    var body: some View {
        Section("Light") {
            LabeledContent("Type", value: typeName)
            ColorRowView(label: "Color", value: light.color)
            LabeledContent("Intensity") { Text(light.intensity, format: .number.precision(.fractionLength(1))) }
            LabeledContent("Range") { Text(light.range, format: .number.precision(.fractionLength(1))) }
        }
    }

    private var typeName: String {
        switch light.type {
        case .directional: "Directional"
        case .point: "Point"
        case .spot: "Spot"
        case .ambient: "Ambient"
        @unknown default: "Unknown"
        }
    }
}

private struct MeshSectionView: View {
    var materials: [any SceneMaterial]
    var castsShadow: Bool
    var receivesShadow: Bool

    var body: some View {
        Section("Mesh") {
            LabeledContent("Casts Shadow", value: castsShadow ? "Yes" : "No")
            LabeledContent("Receives Shadow", value: receivesShadow ? "Yes" : "No")
            ForEach(materials.indices, id: \.self) { index in
                if let material = materials[index] as? BlinnPhongSceneMaterial {
                    Divider()
                    Text("Blinn-Phong Material").font(.subheadline).foregroundStyle(.secondary)
                    colorSourceRow(label: "Ambient", source: material.ambient)
                    colorSourceRow(label: "Diffuse", source: material.diffuse)
                    colorSourceRow(label: "Specular", source: material.specular)
                    LabeledContent("Shininess") { Text(material.shininess, format: .number.precision(.fractionLength(0))) }
                }
            }
        }
    }

    @ViewBuilder
    private func colorSourceRow(label: String, source: BlinnPhongSceneMaterial.Source) -> some View {
        switch source {
        case .color(let color):
            ColorRowView(label: label, value: color)
        default:
            LabeledContent(label, value: "Texture")
        }
    }
}

// MARK: - Supporting Views

private struct VectorRowView: View {
    var label: String
    var value: SIMD3<Float>

    var body: some View {
        LabeledContent(label) {
            HStack {
                Text("X \(value.x, format: .number.precision(.fractionLength(2)))")
                Text("Y \(value.y, format: .number.precision(.fractionLength(2)))")
                Text("Z \(value.z, format: .number.precision(.fractionLength(2)))")
            }
            .monospacedDigit()
            .font(.caption)
        }
    }
}

private struct ColorRowView: View {
    var label: String
    var value: SIMD3<Float>

    var body: some View {
        LabeledContent(label) {
            HStack {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(red: Double(value.x), green: Double(value.y), blue: Double(value.z)))
                    .stroke(.tertiary, lineWidth: 0.5)
                    .frame(width: 16, height: 16)
                    .accessibilityHidden(true)
                Text(verbatim: "(" + [value.x, value.y, value.z].map { $0.formatted(.number.precision(.fractionLength(2))) }.joined(separator: ", ") + ")")
                    .monospacedDigit()
                    .font(.caption)
            }
        }
    }
}

#Preview {
    Form {
        VectorRowView(label: "Position", value: [1, 2.5, -3])
        ColorRowView(label: "Color", value: [0.9, 0.4, 0.1])
    }
    .formStyle(.grouped)
}
