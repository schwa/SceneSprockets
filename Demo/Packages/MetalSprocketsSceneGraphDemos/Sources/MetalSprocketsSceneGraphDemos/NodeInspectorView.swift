import GeometryLite3D
import MetalSprocketsSceneGraph
import MetalSprocketsSceneGraphBlinnPhong
import simd
import SwiftUI

// Form sections describing one node; embed inside a Form.
struct NodeInspectorView: View {
    var node: SceneGraph.Node

    var body: some View {
        generalSection
        transformSection
        contentSection
    }

    // MARK: - General

    @ViewBuilder
    private var generalSection: some View {
        Section("General") {
            LabeledContent("Label", value: node.label ?? "—")
            LabeledContent("Type", value: contentTypeName)
        }
    }

    // MARK: - Transform

    @ViewBuilder
    private var transformSection: some View {
        Section("Transform") {
            let t = node.transform
            VectorRow(label: "Position", value: t.columns.3.xyz)
            VectorRow(label: "X Axis", value: SIMD3(t.columns.0.x, t.columns.0.y, t.columns.0.z))
            VectorRow(label: "Y Axis", value: SIMD3(t.columns.1.x, t.columns.1.y, t.columns.1.z))
            VectorRow(label: "Z Axis", value: SIMD3(t.columns.2.x, t.columns.2.y, t.columns.2.z))
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var contentSection: some View {
        switch node.content {
        case .empty:
            EmptyView()
        case .light(let light):
            lightSection(light)
        case .camera:
            cameraSection
        case .mesh(_, let materials, let castsShadow, let receivesShadow):
            meshSection(materials: materials, castsShadow: castsShadow, receivesShadow: receivesShadow)
        }
    }

    private func lightSection(_ light: Light) -> some View {
        Section("Light") {
            LabeledContent("Type", value: lightTypeName(light.type))
            ColorRow(label: "Color", value: light.color)
            LabeledContent("Intensity") { Text(light.intensity, format: .number.precision(.fractionLength(1))) }
            LabeledContent("Range") { Text(light.range, format: .number.precision(.fractionLength(1))) }
        }
    }

    @ViewBuilder
    private var cameraSection: some View {
        Section("Camera") {
            LabeledContent("Projection", value: "Perspective")
        }
    }

    private func meshSection(materials: [any MetalSprocketsSceneGraph.Material], castsShadow: Bool, receivesShadow: Bool) -> some View {
        Section("Mesh") {
            LabeledContent("Casts Shadow", value: castsShadow ? "Yes" : "No")
            LabeledContent("Receives Shadow", value: receivesShadow ? "Yes" : "No")
            ForEach(materials.indices, id: \.self) { index in
                if let blinnPhong = materials[index] as? BlinnPhongSceneMaterial {
                    blinnPhongSection(blinnPhong)
                }
            }
        }
    }

    private func blinnPhongSection(_ material: BlinnPhongSceneMaterial) -> some View {
        Group {
            Divider()
            Text("Blinn-Phong Material").font(.subheadline).foregroundStyle(.secondary)
            colorSourceRow(label: "Ambient", source: material.ambient)
            colorSourceRow(label: "Diffuse", source: material.diffuse)
            colorSourceRow(label: "Specular", source: material.specular)
            LabeledContent("Shininess") { Text(material.shininess, format: .number.precision(.fractionLength(0))) }
        }
    }

    // MARK: - Helpers

    private var contentTypeName: String {
        switch node.content {
        case .empty: "Empty"
        case .mesh: "Mesh"
        case .light: "Light"
        case .camera: "Camera"
        }
    }

    private func lightTypeName(_ type: Light.LightType) -> String {
        switch type {
        case .directional: "Directional"
        case .point: "Point"
        case .spot: "Spot"
        @unknown default: "Unknown"
        }
    }

    @ViewBuilder
    private func colorSourceRow(label: String, source: BlinnPhongSceneMaterial.Source) -> some View {
        switch source {
        case .color(let color):
            ColorRow(label: label, value: color)
        default:
            LabeledContent(label, value: "Texture")
        }
    }
}

// MARK: - Supporting Views

private struct VectorRow: View {
    var label: String
    var value: SIMD3<Float>

    var body: some View {
        LabeledContent(label) {
            HStack(spacing: 8) {
                Text("X \(value.x, specifier: "%.2f")")
                Text("Y \(value.y, specifier: "%.2f")")
                Text("Z \(value.z, specifier: "%.2f")")
            }
            .monospacedDigit()
            .font(.caption)
        }
    }
}

private struct ColorRow: View {
    var label: String
    var value: SIMD3<Float>

    var body: some View {
        LabeledContent(label) {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(red: Double(value.x), green: Double(value.y), blue: Double(value.z)))
                    .frame(width: 16, height: 16)
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(.tertiary, lineWidth: 0.5))
                Text(String(format: "(%.2f, %.2f, %.2f)", value.x, value.y, value.z))
                    .monospacedDigit()
                    .font(.caption)
            }
        }
    }
}
