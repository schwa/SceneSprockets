import CoreGraphics
import Foundation
import ImageIO
import Metal
import MetalSprockets
import MetalSprocketsSceneGraph
import UniformTypeIdentifiers

// Renders a demo offscreen, without a window: steps it `frames` times at 60 Hz (update, actions, constraints) from
// its initial camera, then draws one frame, with shadows and fog if the demo uses them.
public enum DemoSnapshot {
    public enum Failure: Error, CustomStringConvertible {
        case unknownDemo(String)
        case imageCreationFailed

        public var description: String {
            switch self {
            case .unknownDemo(let id): "No demo with id '\(id)'. Known ids: \(DemoCatalog.demos.map(\.id).joined(separator: ", "))"
            case .imageCreationFailed: "Could not create the image"
            }
        }
    }

    @MainActor
    public static func render(demoID: String, width: Int = 1280, height: Int = 800, frames: Int = 60, values: [String: Float] = [:], configure: (DemoScene) -> Void = { _ in }) throws -> CGImage {
        guard let demo = DemoCatalog.demos.first(where: { $0.id == demoID }) else {
            throw Failure.unknownDemo(demoID)
        }
        let scene = demo.make()
        scene.values.merge(values) { $1 }
        configure(scene)
        let deltaTime: Float = 1 / 60
        for frame in 0..<frames {
            scene.update(time: Float(frame) * deltaTime, deltaTime: deltaTime)
            scene.sceneGraph.advanceActions(by: deltaTime)
            scene.sceneGraph.advanceParticles(by: deltaTime)
            scene.sceneGraph.applyConstraints(pointOfView: scene.initialCameraMatrix, deltaTime: deltaTime)
        }
        let renderer = try OffscreenRenderer(size: CGSize(width: width, height: height), colorUsage: SceneGraphShadows.requiredColorUsage, depthUsage: SceneGraphShadows.requiredDepthUsage)
        let sceneCamera = scene.usesSceneCamera ? scene.sceneGraph.cameraNodes().first?.worldTransform : nil
        let element = SceneGraphElement(sceneGraph: scene.sceneGraph, cameraMatrix: sceneCamera ?? scene.initialCameraMatrix, aspectRatio: Float(width) / Float(height), renderers: scene.renderers, shadows: scene.shadows)
        let texture = try renderer.render(element).texture
        let bytesPerRow = width * 4
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
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

    public static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw Failure.imageCreationFailed
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw Failure.imageCreationFailed
        }
    }
}
