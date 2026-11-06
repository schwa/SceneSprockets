import CoreGraphics
import Foundation
import GoldenImage
@testable import SceneSprocketsDemos
import Testing

// Renders demos offscreen and compares them with stored golden images.
//
// To add or update a golden: delete it (or add a case), run the tests, look at the image named in the failure, and
// copy it into Tests/SceneSprocketsDemosTests/Golden Images.
//
// Goldens are exact renders from the machine that recorded them (Apple silicon); other GPUs may need them
// re-recorded.
@Suite(.serialized)
struct GoldenImageTests {
    static let outputDirectory = FileManager.default.temporaryDirectory.appending(path: "SceneSprocketsDemos-GoldenImages")
    static let psnrThreshold = 40.0

    struct Case: Sendable, CustomTestStringConvertible {
        var name: String
        var demo: String
        var values: [String: Float] = [:]
        var frames = 1
        // A keynote slide title, shown before rendering.
        var slide: String?

        var testDescription: String { name }
    }

    static let cases: [Case] = [
        Case(name: "shadows-directional", demo: "shadows", values: ["Light": 0]),
        Case(name: "shadows-spot", demo: "shadows", values: ["Light": 1]),
        Case(name: "shadows-point", demo: "shadows", values: ["Light": 2]),
        Case(name: "shadows-floor-not-receiving", demo: "shadows", values: ["Floor Receives Shadows": 0]),
        Case(name: "ambient-occlusion-vignette", demo: "shadows", values: ["Shadows": 0, "Ambient Occlusion": 1, "Vignette": 0.6]),
        // Blinn-Phong scenes, recorded before the renderer moved off MetalSprocketsAddOns (#100).
        Case(name: "scenekit-features", demo: "scenekit-features", values: ["Shadows": 0]),
        // Sun, spotlight and a category-2 point light all casting (#71).
        Case(name: "scenekit-features-shadows", demo: "scenekit-features", values: ["Shadows": 1]),
        Case(name: "keynote-materials", demo: "keynote", slide: "Materials"),
        Case(name: "keynote-deformation", demo: "keynote", frames: 30, slide: "Deformation"),
        Case(name: "keynote-performance", demo: "keynote", frames: 30, slide: "Performance"),
        Case(name: "keynote-gltf", demo: "keynote", frames: 30, slide: "glTF & Model I/O"),
        Case(name: "keynote-particles", demo: "keynote", frames: 60, slide: "Particles")
    ]

    @Test(arguments: cases)
    @MainActor
    func matchesGolden(_ testCase: Case) throws {
        let image = try DemoSnapshot.render(demoID: testCase.demo, width: 320, height: 200, frames: testCase.frames, values: testCase.values) { scene in
            if let title = testCase.slide, let keynote = scene as? KeynoteDemo, let index = KeynoteDemo.titles.firstIndex(of: title) {
                keynote.show(slide: index)
            }
        }
        let goldens = try #require(Bundle.module.url(forResource: "Golden Images", withExtension: nil))
        let comparison = GoldenImageComparison(imageDirectory: goldens, psnrThreshold: Self.psnrThreshold, failureOutputDirectory: Self.outputDirectory)
        do {
            let matches = try comparison.image(image: image, matchesGoldenImageNamed: testCase.name)
            #expect(matches, "\(testCase.name) does not match its golden image. Failure images are in \(Self.outputDirectory.path).")
        } catch GoldenImageError.noGoldenImage(let savedTo) {
            Issue.record("No golden image for \(testCase.name). Rendered image saved to \(savedTo?.path ?? "nowhere").")
        }
    }
}
