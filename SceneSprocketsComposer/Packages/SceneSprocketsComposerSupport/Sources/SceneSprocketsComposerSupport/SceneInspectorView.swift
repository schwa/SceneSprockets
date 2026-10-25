import MetalSprocketsPBR
import SceneSprockets
import SwiftUI
import UniformTypeIdentifiers

// Scene-wide settings, shown when no node is selected.
struct SceneInspectorView: View {
    @Bindable var model: EditorModel
    @State private var isImporting = false
    @State private var importError: String?

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
        .alert("Could Not Load Image", isPresented: $importError.isPresent) {
            Button("OK") {
                importError = nil
            }
        } message: {
            Text(importError ?? "")
        }
    }

    private var backgroundSection: some View {
        Section("Background") {
            Picker("Background", selection: $model[environment: "Background"].backgroundKind) {
                ForEach(BackgroundKind.allCases) { kind in
                    Text(kind.rawValue).tag(kind)
                }
            }
            switch model.environment.background {
            case .none:
                EmptyView()

            case .color:
                ColorPicker("Color", selection: $model[environment: "Background Color"].backgroundColor.linearColor)

            case .environment:
                LabeledContent("Blur") {
                    Slider(value: $model[environment: "Background Blur"].backgroundBlur, in: 0 ... 1)
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
                Slider(value: $model[environment: "Environment Intensity"].intensity, in: 0 ... 4)
            }
            LabeledContent("Rotation") {
                Slider(value: $model[environment: "Environment Rotation"].rotationDegrees, in: -180 ... 180)
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
}
