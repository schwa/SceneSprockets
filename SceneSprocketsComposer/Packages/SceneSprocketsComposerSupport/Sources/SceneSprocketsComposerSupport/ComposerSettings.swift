import SwiftUI

// App-wide preferences, stored in user defaults rather than in documents (#189).
public enum GizmoSize: String, CaseIterable, Identifiable, Sendable {
    case small
    case large

    public static let storageKey = "gizmoSize"

    public var id: Self { self }

    var label: String {
        switch self {
        case .small: "Small"
        case .large: "Large"
        }
    }

    // Applied to the size EditorModel picks from the scene bounds.
    var scale: Float {
        switch self {
        case .small: 1
        case .large: 1.75
        }
    }
}

public struct ComposerSettingsView: View {
    @AppStorage(GizmoSize.storageKey)
    private var gizmoSize = GizmoSize.small

    public init() {}

    public var body: some View {
        Form {
            Picker("Gizmo Size", selection: $gizmoSize) {
                ForEach(GizmoSize.allCases) { size in
                    Text(size.label).tag(size)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 360)
    }
}
