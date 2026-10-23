import MetalSprocketsPBR
import SceneSprockets
import SwiftUI
import UniformTypeIdentifiers

// Scene-wide settings, shown when no node is selected.
struct SceneInspectorView: View {
    var model: EditorModel
    @State private var isImporting = false
    @State private var importError: String?

    private enum BackgroundKind: String, CaseIterable, Identifiable {
        case clear = "None"
        case color = "Color"
        case environment = "Environment"

        var id: Self { self }
    }

    var body: some View {
        Form {
            backgroundSection
            environmentSection
        }
        .formStyle(.grouped)
        .fileImporter(isPresented: $isImporting, allowedContentTypes: Self.imageTypes) { result in
            do {
                try model.importEnvironmentImage(from: result.get())
            } catch {
                importError = error.localizedDescription
            }
        }
        .alert("Could Not Load Image", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
            Button("OK") {
                importError = nil
            }
        } message: {
            Text(importError ?? "")
        }
    }

    private var backgroundSection: some View {
        Section("Background") {
            Picker("Background", selection: backgroundKind) {
                ForEach(BackgroundKind.allCases) { kind in
                    Text(kind.rawValue).tag(kind)
                }
            }
            switch model.environment.background {
            case .none:
                EmptyView()

            case .color:
                ColorPicker("Color", selection: backgroundColor)

            case .environment:
                LabeledContent("Blur") {
                    Slider(value: backgroundBlur, in: 0 ... 1)
                }
            }
        }
    }

    private var environmentSection: some View {
        Section("Environment") {
            LabeledContent("Image", value: mapName)
            HStack {
                Button("Choose Image\u{2026}") {
                    isImporting = true
                }
                Button("Use Studio") {
                    update("Environment Image") { $0.map = PBREnvironment.studio }
                }
                .disabled(model.environment.map === PBREnvironment.studio)
            }
            LabeledContent("Intensity") {
                Slider(value: binding(\.intensity, actionName: "Environment Intensity"), in: 0 ... 4)
            }
            LabeledContent("Rotation") {
                Slider(value: rotationDegrees, in: -180 ... 180)
            }
        }
    }

    private static let imageTypes: [UTType] = [UTType(filenameExtension: "hdr"), UTType(filenameExtension: "exr"), .image].compactMap(\.self)

    private var mapName: String {
        switch model.environment.map {
        case nil:
            "Default"

        case let map as PBREnvironment where map === PBREnvironment.studio:
            "Studio"

        default:
            "Custom Image"
        }
    }

    private func update(_ actionName: String, _ change: (inout SceneGraph.Environment) -> Void) {
        var environment = model.environment
        change(&environment)
        model.setEnvironment(environment, actionName: actionName)
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<SceneGraph.Environment, Value>, actionName: String) -> Binding<Value> {
        Binding(get: { model.environment[keyPath: keyPath] }, set: { value in update(actionName) { $0[keyPath: keyPath] = value } })
    }

    private var backgroundKind: Binding<BackgroundKind> {
        Binding(get: {
            switch model.environment.background {
            case .none: .clear
            case .color: .color
            case .environment: .environment
            }
        }, set: { kind in
            update("Background") { environment in
                switch kind {
                case .clear: environment.background = .none
                case .color: environment.background = .color([0.2, 0.2, 0.22, 1])
                case .environment: environment.background = .environment()
                }
            }
        })
    }

    private var backgroundColor: Binding<Color> {
        Binding(get: {
            guard case let .color(color) = model.environment.background else {
                return .black
            }
            return Color(.sRGBLinear, red: Double(color.x), green: Double(color.y), blue: Double(color.z), opacity: Double(color.w))
        }, set: { color in
            let resolved = color.resolve(in: EnvironmentValues())
            update("Background Color") { $0.background = .color([resolved.linearRed, resolved.linearGreen, resolved.linearBlue, resolved.opacity]) }
        })
    }

    private var backgroundBlur: Binding<Float> {
        Binding(get: {
            guard case let .environment(blur) = model.environment.background else {
                return 0
            }
            return blur
        }, set: { blur in
            update("Background Blur") { $0.background = .environment(blur: blur) }
        })
    }

    private var rotationDegrees: Binding<Float> {
        Binding(get: { model.environment.rotation * 180 / .pi }, set: { degrees in
            update("Environment Rotation") { $0.rotation = degrees * .pi / 180 }
        })
    }
}
