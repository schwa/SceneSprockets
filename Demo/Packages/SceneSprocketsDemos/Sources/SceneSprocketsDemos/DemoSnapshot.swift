import CoreGraphics
import Foundation
import ImageIO
import Metal
import MetalSprockets
import SceneSprockets
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
    // Renders `frames` frames one after another, each waiting for the GPU, and returns each frame's wall time in
    // seconds (scene update, encoding and GPU). The first `warmUp` frames are rendered but not timed.
    public static func benchmark(demoID: String, width: Int = 1280, height: Int = 800, frames: Int = 120, warmUp: Int = 10, configure: (DemoScene) -> Void = { _ in }) throws -> [Double] {
        guard let demo = DemoCatalog.demos.first(where: { $0.id == demoID }) else {
            throw Failure.unknownDemo(demoID)
        }
        let scene = demo.make()
        configure(scene)
        let renderer = try OffscreenRenderer(size: CGSize(width: width, height: height), colorUsage: SceneGraphShadows.requiredColorUsage, depthUsage: SceneGraphShadows.requiredDepthUsage)
        let deltaTime: Float = 1 / 60
        var times: [Double] = []
        for frame in 0..<(warmUp + frames) {
            let start = ContinuousClock.now
            scene.update(time: Float(frame) * deltaTime, deltaTime: deltaTime)
            scene.sceneGraph.advanceActions(by: deltaTime)
            scene.sceneGraph.advanceParticles(by: deltaTime)
            scene.sceneGraph.applyConstraints(pointOfView: scene.initialCameraMatrix, deltaTime: deltaTime)
            let sceneCamera = scene.usesSceneCamera ? scene.sceneGraph.cameraNodes().first?.worldTransform : nil
            let element = SceneGraphElement(sceneGraph: scene.sceneGraph, cameraMatrix: sceneCamera ?? scene.initialCameraMatrix, aspectRatio: Float(width) / Float(height), renderers: scene.renderers, shadows: scene.shadows)
            _ = try renderer.render(element)
            let elapsed = ContinuousClock.now - start
            if frame >= warmUp {
                times.append(Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) * 1e-18)
            }
        }
        return times
    }

    @MainActor
    public static func render(demoID: String, width: Int = 1280, height: Int = 800, frames: Int = 60, values: [String: Float] = [:], configure: (DemoScene) -> Void = { _ in }) throws -> CGImage {
        guard let demo = DemoCatalog.demos.first(where: { $0.id == demoID }) else {
            throw Failure.unknownDemo(demoID)
        }
        let scene = demo.make()
        scene.values.merge(values) { $1 }
        configure(scene)
        let renderer = try OffscreenRenderer(size: CGSize(width: width, height: height), colorUsage: SceneGraphShadows.requiredColorUsage, depthUsage: SceneGraphShadows.requiredDepthUsage)
        func makeElement() -> SceneGraphElement {
            let sceneCamera = scene.usesSceneCamera ? scene.sceneGraph.cameraNodes().first?.worldTransform : nil
            return SceneGraphElement(sceneGraph: scene.sceneGraph, cameraMatrix: sceneCamera ?? scene.initialCameraMatrix, aspectRatio: Float(width) / Float(height), renderers: scene.renderers, shadows: scene.shadows)
        }
        let deltaTime: Float = 1 / 60
        for frame in 0..<frames {
            scene.update(time: Float(frame) * deltaTime, deltaTime: deltaTime)
            scene.sceneGraph.advanceActions(by: deltaTime)
            scene.sceneGraph.advanceParticles(by: deltaTime)
            scene.sceneGraph.applyConstraints(pointOfView: scene.initialCameraMatrix, deltaTime: deltaTime)
            // Particles simulate on the GPU one step per rendered frame, so draw the frames before the last too.
            if frame < frames - 1, scene.sceneGraph.hasParticleSystems {
                _ = try renderer.render(makeElement())
            }
        }
        let texture = try renderer.render(makeElement()).texture
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

    // Records `seconds` of a demo to a movie at `frameRate`, stepping it one frame at a time like render(...). Calls
    // `progress` with each frame index.
    @MainActor
    public static func video(
        demoID: String,
        to url: URL,
        width: Int = 1920,
        height: Int = 1080,
        seconds: Double,
        frameRate: Double = 60,
        values: [String: Float] = [:],
        configure: (DemoScene) -> Void = { _ in },
        progress: (_ frame: Int, _ frameCount: Int) -> Void = { _, _ in }
    ) async throws {
        guard let demo = DemoCatalog.demos.first(where: { $0.id == demoID }) else {
            throw Failure.unknownDemo(demoID)
        }
        let scene = demo.make()
        scene.values.merge(values) { $1 }
        configure(scene)
        // The scene's post passes (shadow mask, fog, AO, soft particles) read and write the targets outside the pass.
        let renderer = try OffscreenVideoRenderer(
            size: CGSize(width: width, height: height),
            frameRate: frameRate,
            outputURL: url,
            pixelFormat: .bgra8Unorm_srgb,
            colorUsage: SceneGraphShadows.requiredColorUsage,
            depthUsage: SceneGraphShadows.requiredDepthUsage,
            clearDepth: 0
        )
        let deltaTime = Float(1 / frameRate)
        let frameCount = Int((seconds * frameRate).rounded())
        for frame in 0..<frameCount {
            scene.update(time: Float(frame) * deltaTime, deltaTime: deltaTime)
            scene.sceneGraph.advanceActions(by: deltaTime)
            scene.sceneGraph.advanceParticles(by: deltaTime)
            scene.sceneGraph.applyConstraints(pointOfView: scene.initialCameraMatrix, deltaTime: deltaTime)
            let sceneCamera = scene.usesSceneCamera ? scene.sceneGraph.cameraNodes().first?.worldTransform : nil
            try await renderer.render(SceneGraphElement(sceneGraph: scene.sceneGraph, cameraMatrix: sceneCamera ?? scene.initialCameraMatrix, aspectRatio: Float(width) / Float(height), renderers: scene.renderers, shadows: scene.shadows))
            progress(frame, frameCount)
        }
        try await renderer.finalize()
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
