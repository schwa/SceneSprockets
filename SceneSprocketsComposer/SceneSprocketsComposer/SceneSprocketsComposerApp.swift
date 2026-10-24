import SceneSprocketsComposerSupport
import SwiftUI

@main
struct SceneSprocketsComposerApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: { ComposerDocument() }, editor: { configuration in
            ComposerView(document: configuration.document)
        })
        .commands {
            ComposerCommands()
        }
        #if os(macOS)
        Settings {
            ComposerSettingsView()
        }
        #endif
    }
}
