import CoreGraphics
import Foundation
import GeometryLite3D
import ImageIO
import Metal
import MetalSprockets
import SceneSprockets
import SceneSprocketsBlinnPhong
import SceneSprocketsPBR
import UniformTypeIdentifiers

// Preview.png in the document bundle, so Quick Look can show the scene without loading it or starting Metal.
public enum DocumentPreview {
    public static let fileName = "Preview.png"
    static let size = CGSize(width: 1_024, height: 768)

    public enum Failure: Error {
        case imageCreationFailed
    }

    // From the first camera node, or a default editor camera framing the scene. Runs on any thread: saving on quit
    // calls it from a background queue (#204).
    static func render(_ sceneGraph: SceneGraph) throws -> CGImage {
        let width = Int(size.width)
        let height = Int(size.height)
        let renderer = try OffscreenRenderer(size: size)
        var camera = EditorCamera()
        if let bounds = sceneGraph.bounds {
            camera.frame(bounds, fieldOfView: 60)
        }
        let element = SceneGraphElement(
            sceneGraph: sceneGraph,
            cameraMatrix: sceneGraph.cameraNodes().first?.worldTransform ?? camera.matrix,
            aspectRatio: Float(width) / Float(height),
            renderers: [BlinnPhongMaterialRenderer(), PBRMaterialRenderer()],
            // Without a camera node the element draws nothing unless it has a default camera.
            // Like Camera.default, which is main-actor isolated.
            defaultCamera: Camera(projection: PerspectiveProjection(verticalAngleOfView: .degrees(60), depthMode: .standard(zClip: 0.01 ... 1_000))),
            defaultLight: Light(type: .directional, color: [1, 1, 1], intensity: 1)
        )
        let texture = try renderer.render(element).texture
        let bytesPerRow = width * 4
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
              let data = context.data
        else {
            throw Failure.imageCreationFailed
        }
        texture.getBytes(data, bytesPerRow: bytesPerRow, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        guard let image = context.makeImage() else {
            throw Failure.imageCreationFailed
        }
        return image
    }

    static func write(_ sceneGraph: SceneGraph, into bundle: URL) throws {
        let image = try render(sceneGraph)
        let url = bundle.appendingPathComponent(fileName)
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw Failure.imageCreationFailed
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw Failure.imageCreationFailed
        }
    }

    // The saved preview in a document bundle, if there is one.
    public static func image(inBundleAt url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url.appendingPathComponent(fileName) as CFURL, nil) else {
            return nil
        }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
