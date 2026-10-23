import Cocoa
import Quartz
import SceneSprocketsComposerSupport
import SwiftUI

final class PreviewViewController: NSViewController, QLPreviewingController {
    override func loadView() {
        view = NSView()
    }

    // swiftlint:disable:next async_without_await
    func preparePreviewOfFile(at url: URL) async throws {
        let document = try ComposerDocument(contentsOf: url)
        let hostingView = NSHostingView(rootView: QuickLookPreviewView(document: document))
        hostingView.autoresizingMask = [.width, .height]
        hostingView.frame = view.bounds
        view.addSubview(hostingView)
    }
}
