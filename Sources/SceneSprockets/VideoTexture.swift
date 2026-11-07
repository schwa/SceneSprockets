import AVFoundation
import CoreVideo
import Metal
import QuartzCore

/// A texture that shows an `AVPlayer`'s video, for any material slot that takes a texture, like SceneKit's
/// `material.diffuse.contents = player`.
///
/// The ``texture`` stays the same object; ``update(atHostTime:)`` copies the player's latest frame into it. Call it
/// once per frame, for example from `SceneViewDelegate.sceneView(updateAtTime:deltaTime:)`. The texture is sRGB, with
/// the top row of the video at texture coordinate `v = 0`, as for ``MaterialTexture``.
public final class VideoTexture {
    /// The player whose video the texture shows. Control playback (play, pause, seek) with it.
    public let player: AVPlayer
    /// The texture to give to materials.
    public let texture: MTLTexture

    private let output: AVPlayerItemVideoOutput
    private let cache: CVMetalTextureCache
    private let commandQueue: MTLCommandQueue

    /// Creates a video texture for a player.
    ///
    /// - Parameters:
    ///   - player: The player. Its current item gets a video output.
    ///   - width: The texture width, usually the video's width in pixels.
    ///   - height: The texture height, usually the video's height in pixels.
    ///   - device: The device for the texture.
    /// - Throws: An error if the texture, texture cache or command queue cannot be made.
    public init(player: AVPlayer, width: Int, height: Int, device: MTLDevice) throws {
        self.player = player
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm_srgb, width: width, height: height, mipmapped: false)
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = .private
        guard let texture = device.makeTexture(descriptor: descriptor), let commandQueue = device.makeCommandQueue() else {
            throw CocoaError(.featureUnsupported)
        }
        texture.label = "VideoTexture"
        self.texture = texture
        self.commandQueue = commandQueue
        var cache: CVMetalTextureCache?
        guard CVMetalTextureCacheCreate(nil, nil, device, nil, &cache) == kCVReturnSuccess, let cache else {
            throw CocoaError(.featureUnsupported)
        }
        self.cache = cache
        output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferMetalCompatibilityKey as String: true
        ])
        player.currentItem?.add(output)
    }

    /// Loads a video file into a new player, with a texture the size of its video.
    ///
    /// - Parameters:
    ///   - url: The video file.
    ///   - device: The device for the texture.
    /// - Returns: The video texture. Its player is paused; call `player.play()` to start.
    /// - Throws: An error if the file has no video track or the texture cannot be made.
    public static func load(contentsOf url: URL, device: MTLDevice) async throws -> VideoTexture {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let (naturalSize, transform) = try await track.load(.naturalSize, .preferredTransform)
        let size = naturalSize.applying(transform)
        let player = AVPlayer(playerItem: AVPlayerItem(asset: asset))
        return try VideoTexture(player: player, width: Int(abs(size.width).rounded()), height: Int(abs(size.height).rounded()), device: device)
    }

    /// Copies the player's frame for `hostTime` into ``texture``, if there is a new one.
    ///
    /// - Parameter hostTime: The host time of the frame to show. The default is now.
    /// - Returns: Whether a new frame was copied.
    @discardableResult
    public func update(atHostTime hostTime: CFTimeInterval = CACurrentMediaTime()) -> Bool {
        let itemTime = output.itemTime(forHostTime: hostTime)
        guard output.hasNewPixelBuffer(forItemTime: itemTime), let pixelBuffer = output.copyPixelBuffer(forItemTime: itemTime, itemTimeForDisplay: nil) else {
            return false
        }
        return copy(pixelBuffer)
    }

    // Blits a BGRA pixel buffer into the texture. Sizes that differ copy the overlapping part.
    func copy(_ pixelBuffer: CVPixelBuffer) -> Bool {
        let width = CVPixelBufferGetWidth(pixelBuffer), height = CVPixelBufferGetHeight(pixelBuffer)
        var metalTexture: CVMetalTexture?
        guard CVMetalTextureCacheCreateTextureFromImage(nil, cache, pixelBuffer, nil, .bgra8Unorm_srgb, width, height, 0, &metalTexture) == kCVReturnSuccess,
              let metalTexture, let source = CVMetalTextureGetTexture(metalTexture),
              let commandBuffer = commandQueue.makeCommandBuffer(), let blit = commandBuffer.makeBlitCommandEncoder() else {
            return false
        }
        let size = MTLSize(width: min(width, texture.width), height: min(height, texture.height), depth: 1)
        blit.copy(from: source, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(), sourceSize: size, to: texture, destinationSlice: 0, destinationLevel: 0, destinationOrigin: MTLOrigin())
        blit.endEncoding()
        // Keeps the pixel buffer's texture alive until the GPU has copied it. Only released there, never used.
        struct Retained: @unchecked Sendable {
            let texture: CVMetalTexture
        }
        let retained = Retained(texture: metalTexture)
        commandBuffer.addCompletedHandler { _ in _ = retained }
        commandBuffer.commit()
        return true
    }
}
