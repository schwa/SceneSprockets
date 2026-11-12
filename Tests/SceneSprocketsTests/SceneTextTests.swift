import CoreGraphics
import Foundation
import GeometryLite3D
import Metal
import MetalSprockets
@testable import SceneSprockets
@testable import SceneSprocketsBlinnPhong
import simd
import Testing

// #119: flat 2D text at a node, drawn with Slug.

// The fraction of red pixels in a 64×64 render of a big red "█" in front of the camera, on a black background.
@MainActor
private func redCoverage(text: SceneText?, visible: Bool = true) throws -> Double {
    let root = SceneGraph.Node()
    root.addChild(SceneGraph.Node(transform: .init(translation: [0, 0, 5]), content: .camera(Camera(projection: PerspectiveProjection(verticalAngleOfView: .degrees(60))))))
    let textNode = SceneGraph.Node(transform: .init(translation: [-1, -1, 0]))
    textNode.text = text
    textNode.isVisible = visible
    root.addChild(textNode)
    let sceneGraph = SceneGraph(root: root)
    sceneGraph.environment.background = .color([0, 0, 0, 1])
    let size = 64
    let renderer = try OffscreenRenderer(size: CGSize(width: size, height: size))
    let texture = try renderer.render(SceneGraphElement(sceneGraph: sceneGraph, aspectRatio: 1, renderers: [BlinnPhongMaterialRenderer()])).texture
    var pixels = [SIMD4<UInt8>](repeating: .zero, count: size * size)
    texture.getBytes(&pixels, bytesPerRow: size * 4, from: MTLRegionMake2D(0, 0, size, size), mipmapLevel: 0)
    // BGRA.
    let red = pixels.filter { $0.z > 200 && $0.x < 40 && $0.y < 40 }.count
    return Double(red) / Double(pixels.count)
}

@Test(.enabled(if: deviceSupportsMetal4))
@MainActor
func sceneTextDraws() throws {
    let text = SceneText("█", fontName: "Menlo", fontSize: 2, color: [1, 0, 0, 1])
    #expect(try redCoverage(text: nil) == 0)
    let coverage = try redCoverage(text: text)
    #expect(coverage > 0.05, "\(coverage)")
    #expect(try redCoverage(text: text, visible: false) == 0)
}

@Test
func sceneTextRoundTripsThroughArchive() throws {
    let text = SceneText("Hello\nWorld", fontName: "Menlo", fontSize: 0.5, color: [1, 0.5, 0, 1], maximumWidth: 3)
    let decoded = try JSONDecoder().decode(SceneText.self, from: JSONEncoder().encode(text))
    #expect(decoded == text)
}

@Test
func sceneTextIsCopiedByClone() {
    let node = SceneGraph.Node()
    node.text = SceneText("Label")
    #expect(node.clone().text == SceneText("Label"))
}
