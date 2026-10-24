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
        // The saved PNG avoids loading the scene and starting Metal; older documents have none.
        let hostingView: NSView
        if let image = DocumentPreview.image(inBundleAt: url) {
            hostingView = NSHostingView(rootView: Image(decorative: image, scale: 1).resizable().scaledToFit())
        } else {
            hostingView = NSHostingView(rootView: QuickLookPreviewView(document: try ComposerDocument(contentsOf: url)))
        }
        hostingView.autoresizingMask = [.width, .height]
        hostingView.frame = view.bounds
        view.addSubview(hostingView)
    }
}
