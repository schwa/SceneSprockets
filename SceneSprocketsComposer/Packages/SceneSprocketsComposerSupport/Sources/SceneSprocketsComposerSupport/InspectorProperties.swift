import GeometryLite3D
import Interaction3D
import MetalSprocketsPBR
import SceneSprockets
import SceneSprocketsBlinnPhong
import SceneSprocketsPBR
import simd
import SwiftUI

// Writable properties the inspectors project with key paths ($model.selectedLabel, $light.innerCone, ...), instead
// of building Binding(get:set:) in body (#224). Node properties act on the selected node.
extension EditorModel {
    var selectedLabel: String {
        get {
            observe(.label)
            return selectedNode?.label ?? ""
        }
        set {
            if let node = selectedNode {
                setLabel(newValue.isEmpty ? nil : newValue, of: node)
            }
        }
    }

    var selectedIsVisible: Bool {
        get { selectedNode.map(isVisible) ?? false }
        set {
            if let node = selectedNode {
                setVisible(newValue, node)
            }
        }
    }

    var selectedIsActive: Bool {
        get { selectedNode.map(isActive) ?? false }
        set {
            if let node = selectedNode {
                setActive(newValue, node)
            }
        }
    }

    var selectedIsLocked: Bool {
        get { selectedNode.map { lockedNodes.contains($0.id) } ?? false }
        set {
            if let node = selectedNode {
                setLocked(newValue, node)
            }
        }
    }

    var selectedTransform: Transform3D {
        get { selectedNode.map(localTransform(of:)) ?? Transform3D() }
        set {
            guard let node = selectedNode else {
                return
            }
            let previous = node.transform
            setTransform(newValue, of: node, undoTo: previous)
        }
    }

    var selectedLight: Light? {
        guard let node = selectedNode else {
            return nil
        }
        observe(.content)
        guard case .light(let light) = node.content else {
            return nil
        }
        return light
    }

    // For the light inspector. Never optional: SwiftUI can still read a binding after the selection stopped being a
    // light (the assistant changes things between view updates), and an unwrapped optional binding then traps
    // (#241). Reads a default light and ignores writes when there is no selected light.
    var selectedLightForEditing: Light {
        get { selectedLight ?? Light(type: .point) }
        set {
            if let node = selectedNode, selectedLight != nil {
                setLight(newValue, of: node)
            }
        }
    }

    // Shared values for a multiple selection: on when every node has it on; setting sets all, as one undo step.
    var selectionIsVisible: Bool {
        get { selectedNodes.allSatisfy(isVisible) }
        set { editSelection("Visibility") { model, node in model.setVisible(newValue, node) } }
    }

    var selectionIsActive: Bool {
        get { selectedNodes.allSatisfy(isActive) }
        set { editSelection("Active") { model, node in model.setActive(newValue, node) } }
    }

    var selectionIsLocked: Bool {
        get { selectedNodes.allSatisfy { lockedNodes.contains($0.id) } }
        set { editSelection("Lock", includesLocked: true) { model, node in model.setLocked(newValue, node) } }
    }

    var selectionBaseColor: SIMD3<Float> {
        get { selectedNodes.lazy.compactMap { self.materials(of: $0).first }.first.map(Self.baseColor(of:)) ?? .one }
        set { editSelection("Color") { model, node in model.setBaseColor(newValue, of: node) } }
    }

    // The scene environment; each edit is one undo step named `actionName`.
    subscript(environment actionName: String) -> SceneGraph.Environment {
        get { environment }
        set { setEnvironment(newValue, actionName: actionName) }
    }

    // Material `index` of the selected node, nil when it is missing or another type.
    subscript(material index: Int) -> (any SceneMaterial)? {
        guard let node = selectedNode else {
            return nil
        }
        let materials = materials(of: node)
        return materials.indices.contains(index) ? materials[index] : nil
    }

    // The material subscripts below are never optional, for the same reason as selectedLightForEditing (#241): a
    // default when the material is missing or another kind, and writes that MaterialEdit skips in that case.
    subscript(blinnPhong index: Int, actionName actionName: String) -> BlinnPhongSceneMaterial {
        get { self[material: index] as? BlinnPhongSceneMaterial ?? BlinnPhongSceneMaterial(ambient: .color(0), diffuse: .color(0.8), specular: .color(0), shininess: 32) }
        set {
            if let node = selectedNode {
                try? editMaterials(of: node, at: index, actionName: actionName, [.blinnPhong { $0 = newValue }])
            }
        }
    }

    subscript(pbrUniforms index: Int, actionName actionName: String) -> PBRMaterialUniforms {
        get { (self[material: index] as? PBRSceneMaterial)?.pbrMaterial.uniforms ?? .defaults(baseColor: [1, 1, 1, 1]) }
        set {
            if let node = selectedNode {
                try? editMaterials(of: node, at: index, actionName: actionName, [.uniforms { $0 = newValue }])
            }
        }
    }

    subscript(pbrDoubleSided index: Int) -> Bool {
        get { (self[material: index] as? PBRSceneMaterial)?.pbrMaterial.doubleSided ?? false }
        set {
            if let node = selectedNode {
                try? editMaterials(of: node, at: index, actionName: "Double Sided", [.doubleSided(newValue)])
            }
        }
    }

    subscript(materialKind index: Int) -> MaterialKind {
        get { self[material: index].flatMap(MaterialKind.init) ?? .blinnPhong }
        set {
            if let node = selectedNode {
                try? editMaterials(of: node, at: index, actionName: "Material Type", [.kind(newValue)])
            }
        }
    }
}

// Linear RGB(A) in the scene, shown as a SwiftUI Color. Alpha is not linearized.
extension SIMD3 where Scalar == Float {
    var linearColor: Color {
        get { Color(.sRGBLinear, red: Double(x), green: Double(y), blue: Double(z)) }
        set {
            let resolved = newValue.resolve(in: EnvironmentValues())
            self = [resolved.linearRed, resolved.linearGreen, resolved.linearBlue]
        }
    }

    // One component as a Double, for numeric fields.
    subscript(double index: Int) -> Double {
        get { Double(self[index]) }
        set { self[index] = Float(newValue) }
    }
}

extension SIMD4 where Scalar == Float {
    var linearColor: Color {
        get { Color(.sRGBLinear, red: Double(x), green: Double(y), blue: Double(z), opacity: Double(w)) }
        set {
            let resolved = newValue.resolve(in: EnvironmentValues())
            self = [resolved.linearRed, resolved.linearGreen, resolved.linearBlue, resolved.opacity]
        }
    }
}

extension Int32 {
    var isOn: Bool {
        get { self != 0 }
        set { self = newValue ? 1 : 0 }
    }
}

extension Optional {
    // For alert(isPresented:): dismissing clears the value.
    var isPresent: Bool {
        get { self != nil }
        set {
            if !newValue {
                self = nil
            }
        }
    }
}

extension Transform3D {
    // Pitch, yaw, roll in degrees, converted as CameraPose does.
    var rotationDegrees: SIMD3<Float> {
        get { CameraPose(matrix: simd_float4x4(rotation)).rotationDegrees }
        set { rotation = Rotation3D(simd_quatf(CameraPose(position: .zero, rotationDegrees: newValue).matrix)) }
    }
}

extension Light {
    // Off: the light reaches any distance.
    var isRangeLimited: Bool {
        get { range.isFinite }
        set { range = newValue ? 10 : .infinity }
    }

    var innerCone: Angle {
        get { .radians(Double(innerConeAngle)) }
        set { self = LightEditing.settingCone(\.innerConeAngle, to: Float(newValue.radians), of: self) }
    }

    var outerCone: Angle {
        get { .radians(Double(outerConeAngle)) }
        set { self = LightEditing.settingCone(\.outerConeAngle, to: Float(newValue.radians), of: self) }
    }
}

extension BlinnPhongSceneMaterial.Source {
    // The color, or black for a texture. Setting replaces a texture with the color.
    var color: SIMD3<Float> {
        get {
            if case let .color(color) = self {
                return color
            }
            return .zero
        }
        set { self = .color(newValue) }
    }
}

extension PBRMaterialUniforms {
    // Off: the volume does not absorb (attenuation distance is infinite).
    var absorbsLight: Bool {
        get { attenuationDistance.isFinite }
        set { attenuationDistance = newValue ? 1 : .infinity }
    }
}

enum BackgroundKind: String, CaseIterable, Identifiable {
    case clear = "None"
    case color = "Color"
    case environment = "Environment"
    case gradient = "Gradient"

    var id: Self { self }
}

extension SceneGraph.Environment {
    var backgroundKind: BackgroundKind {
        get {
            switch background {
            case .none: .clear
            case .color: .color
            case .environment: .environment
            case .gradient: .gradient
            }
        }
        set {
            switch newValue {
            case .clear: background = .none
            case .color: background = .color([0.2, 0.2, 0.22, 1])
            case .environment: background = .environment()
            case .gradient: background = .gradient(Self.defaultSkyGradient)
            }
        }
    }

    var backgroundColor: SIMD4<Float> {
        get {
            if case let .color(color) = background {
                return color
            }
            return [0, 0, 0, 1]
        }
        set { background = .color(newValue) }
    }

    static let defaultSkyGradient = SkyGradient(zenith: [0.15, 0.35, 0.8], horizon: [0.75, 0.85, 0.95], ground: [0.25, 0.22, 0.2])

    var skyGradient: SkyGradient {
        get {
            if case let .gradient(gradient) = background {
                return gradient
            }
            return Self.defaultSkyGradient
        }
        set { background = .gradient(newValue) }
    }

    var backgroundBlur: Float {
        get {
            if case let .environment(blur) = background {
                return blur
            }
            return 0
        }
        set { background = .environment(blur: newValue) }
    }

    var rotationDegrees: Float {
        get { rotation * 180 / .pi }
        set { rotation = newValue * .pi / 180 }
    }
}
