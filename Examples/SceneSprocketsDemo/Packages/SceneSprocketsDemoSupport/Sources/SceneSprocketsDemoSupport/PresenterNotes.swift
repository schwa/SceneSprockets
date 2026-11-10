import Observation
import SwiftUI

// What the presenter notes window shows: the keynote's current slide and its notes (#331). The keynote updates it
// whenever its slide changes.
@MainActor
@Observable
final class PresenterNotes {
    static let shared = PresenterNotes()

    var slideIndex = 0
    var slideCount = 0
    var title = ""
    var notes = ""
    var nextTitle: String?
}

struct PresenterNotesView: View {
    let model: PresenterNotes

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text(model.title.isEmpty ? "No keynote running" : model.title)
                    .font(.largeTitle.bold())
                Spacer()
                if model.slideCount > 0 {
                    Text("\(model.slideIndex + 1) of \(model.slideCount)")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            ScrollView {
                Text(model.notes.isEmpty ? "No notes for this slide." : model.notes)
                    .font(.title2)
                    .foregroundStyle(model.notes.isEmpty ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            if let nextTitle = model.nextTitle {
                Divider()
                Text("Next: \(nextTitle)")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(24)
        .frame(minWidth: 480, minHeight: 320)
    }
}

#if os(macOS)
// A separate window, for example on the presenter's display. Window > Presenter Notes opens it.
struct PresenterNotesWindow: Scene {
    var body: some Scene {
        Window("Presenter Notes", id: "presenter-notes") {
            PresenterNotesView(model: .shared)
        }
        .keyboardShortcut("p", modifiers: [.command, .option])
    }
}
#endif
