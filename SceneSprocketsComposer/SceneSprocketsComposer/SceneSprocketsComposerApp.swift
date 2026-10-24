import SceneSprocketsComposerSupport
import SwiftUI

@main
struct SceneSprocketsComposerApp: App {
    // Assistant sign-in, shared by every document window and Settings.
    @State private var credentials = ComposerAssistant.makeCredentials()

    var body: some Scene {
        DocumentGroup(newDocument: { ComposerDocument() }, editor: { configuration in
            ComposerView(document: configuration.document)
                .environment(credentials)
        })
        .commands {
            ComposerCommands()
        }
        #if os(macOS)
        Settings {
            ComposerSettingsView()
                .environment(credentials)
        }
        #endif
    }
}
