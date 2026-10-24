import CollaborationKit
import CollaborationKitUI
import SwiftUI

// The AI assistant (#190), set up like Phosphor's: the app owns the credentials and puts them in the environment of
// every window, including Settings; each document has its own conversation, owned by ComposerView so it survives
// sidebar tab switches. Scene tools come in #191.
public enum ComposerAssistant {
    @MainActor
    public static func makeCredentials() -> CollaborationCredentials {
        CollaborationCredentials(
            store: KeychainCredentialStore(service: "io.schwa.SceneSprocketsComposer"),
            defaultsKey: "composer.assistant.backend"
        )
    }

    static let systemPrompt = """
    You are the assistant in SceneSprockets Composer, a macOS editor for 3D scene graphs. The user builds scenes from \
    shapes, lights and cameras, and edits their transforms and materials. Use the tools to read and change the open \
    scene: query first to see the nodes, their ids and the selection, then create, update, select and delete by id. \
    Combine them for tasks such as aligning, distributing or recoloring; compute positions from the bounds query \
    returns. +Y is up and units are meters; shapes are about 1 unit across. The user can undo all of a reply's \
    changes in one step. Be concise.
    """

    @MainActor
    static func makeStore(credentials: CollaborationCredentials, model: EditorModel) -> ConversationStore? {
        guard credentials.hasCredentials, let provider = try? credentials.makeProvider() else {
            return nil
        }
        let tools = SceneTools(model: model)
        return ConversationStore(session: LLMSession(provider: provider, system: systemPrompt, tools: tools.collaborationTools))
    }
}

struct AssistantPanel: View {
    let store: ConversationStore?
    @Environment(CollaborationCredentials.self)
    private var credentials

    var body: some View {
        if let store {
            CollaborationChatView(store: store)
                .collaborationComposerBorderStyle(.glow)
                .collaborationEmptyPlaceholder {
                    ContentUnavailableView {
                        Label("Ask About Your Scene", systemImage: "sparkles")
                    } description: {
                        Text("Ask about 3D composition, lighting or materials.")
                    }
                }
                .collaborationComposerHeader {
                    HStack(spacing: 4) {
                        Image(systemName: "cpu")
                        Text("\(credentials.backend.displayName) \u{00B7} \(credentials.selectedModel)")
                        Spacer()
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
                .collaborationMissingCredentialsPlaceholder {
                    missingCredentials
                }
                .collaborationSessionCommands(store: store)
        } else {
            missingCredentials
        }
    }

    private var missingCredentials: some View {
        ContentUnavailableView {
            Label("Sign In to Use the Assistant", systemImage: "key.horizontal")
        } description: {
            Text("Add an API key or sign in under Settings \u{2192} Assistant.")
        } actions: {
            #if os(macOS)
            SettingsLink {
                Text("Open Settings\u{2026}")
            }
            #endif
        }
    }
}
