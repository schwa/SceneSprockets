import CoreGraphics
import QuickLookThumbnailing
import SceneSprocketsComposerSupport

// Finder thumbnails from the Preview.png that saving writes into each document (#175, #194). Documents without one
// fail, and Finder shows the generic icon.
final class ThumbnailProvider: QLThumbnailProvider {
    enum Failure: Error {
        case noPreview
    }

    // swiftlint:disable:next unneeded_escaping - the superclass signature has @escaping
    override func provideThumbnail(for request: QLFileThumbnailRequest, _ handler: @escaping (QLThumbnailReply?, (any Error)?) -> Void) {
        guard let image = DocumentPreview.image(inBundleAt: request.fileURL) else {
            handler(nil, Failure.noPreview)
            return
        }
        let size = Self.fittedSize(image: CGSize(width: image.width, height: image.height), within: request.maximumSize)
        let reply = QLThumbnailReply(contextSize: size) { context in
            context.draw(image, in: CGRect(origin: .zero, size: size))
            return true
        }
        handler(reply, nil)
    }

    // The image scaled to fit, keeping its aspect ratio.
    static func fittedSize(image: CGSize, within maximum: CGSize) -> CGSize {
        guard image.width > 0, image.height > 0 else {
            return maximum
        }
        let scale = min(maximum.width / image.width, maximum.height / image.height)
        return CGSize(width: (image.width * scale).rounded(), height: (image.height * scale).rounded())
    }
}
