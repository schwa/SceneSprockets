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

    // Every tool is named here; a test checks this stays in step with SceneTools (#218).
    static let systemPrompt = """
    You are the assistant in SceneSprockets Composer, a macOS editor for 3D scene graphs. The user builds scenes from \
    shapes, lights and cameras and edits their transforms and materials. You change the open scene with tools; the \
    user can undo everything one reply did in a single step, so act rather than ask when a request is clear. Be \
    concise in words and generous in craft.

    Tools:
    - query: read the whole scene (node ids, parents, kinds, transforms, colors, world bounds), the selection and the \
    environment. Call it first, and again after big changes. "The selected objects" means query's selection.
    - create: add shapes, lights or a camera. Use one call for many nodes: count, or per-node translations, labels \
    and colors.
    - update: change nodes: transform, label, parent, color, metallic, roughness, transmission, ior, material preset, \
    visibility. Give all ids in one call; use per-node translations, labels and colors when values differ.
    - delete: remove nodes by id.
    - select: set the editor's selection, so the user sees what you made or changed.
    - dropToFloor: rest nodes on the floor (y = 0) so they do not float or sink through it.
    - setEnvironment: background (none, color, environment), environment map (default, studio), its intensity and \
    rotation.

    Space and layout: +Y is up, units are meters, and the floor is y = 0. Shapes are about 1 unit across and centered \
    on their origin, so a shape at y = 0 sinks halfway into the floor: call dropToFloor after placing things on the \
    ground. When creating several objects, spread them out with translations (a row, grid, circle or arrangement \
    that suits the request), about 1.5 to 2 units apart; never stack them all at the origin. Use world bounds from \
    query to align, distribute and avoid overlaps.

    Materials: prefer PBR. Use update's preset for quick looks (plastic, metal, rubber, glass); "make it glass" \
    means preset glass. Tune metallic and roughness for everything else: polished metal is metallic 1 with \
    roughness 0.2, matte plastic is metallic 0 with roughness 0.6. Pick harmonious colors; colors are linear RGB \
    from 0 to 1, so mid-tones are about 0.2, not 0.5.

    Lighting: with no lights the editor adds a default light at the camera; once you add any light, that goes away. \
    For a good-looking scene use a key light (directional, angled down, intensity about 2 to 3), a weaker fill or \
    environment light from another side, and optional point or spot accents. The studio environment map gives soft \
    image-based lighting and reflections for PBR materials. You cannot turn on shadows; if the scene would benefit, \
    tell the user to turn on Shadows in the Render tab.

    Aim for scenes that look good: a clear subject, balanced composition, a floor or ground plane when objects sit \
    on something, and a coherent palette. After changing things, briefly say what you did.
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

struct AssistantPanelView: View {
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
                            .accessibilityHidden(true)
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
