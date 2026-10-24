import CollaborationKitUI
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

    // Needs CollaborationCredentials in the environment for the Assistant tab.
    public var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") {
                Form {
                    Picker("Gizmo Size", selection: $gizmoSize) {
                        ForEach(GizmoSize.allCases) { size in
                            Text(size.label).tag(size)
                        }
                    }
                }
                .formStyle(.grouped)
            }
            Tab("Assistant", systemImage: "bubble.left.and.text.bubble.right") {
                CollaborationSettingsView()
            }
        }
        .frame(minWidth: 520, minHeight: 420)
    }
}
