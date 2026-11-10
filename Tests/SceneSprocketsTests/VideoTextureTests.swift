import AVFoundation
import CoreVideo
import Metal
@testable import SceneSprockets
import Testing

// #342: video frames reach a stable texture that materials can use.
@Test
func videoFramesAreCopiedIntoTheTexture() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let video = try VideoTexture(player: AVPlayer(), width: 8, height: 4)
    #expect(video.texture.pixelFormat == .bgra8Unorm_srgb)

    // A Metal-compatible BGRA frame, solid red.
    var pixelBuffer: CVPixelBuffer?
    let attributes: [String: Any] = [kCVPixelBufferMetalCompatibilityKey as String: true, kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any]]
    #expect(CVPixelBufferCreate(nil, 8, 4, kCVPixelFormatType_32BGRA, attributes as CFDictionary, &pixelBuffer) == kCVReturnSuccess)
    let frame = try #require(pixelBuffer)
    CVPixelBufferLockBaseAddress(frame, [])
    let rowBytes = CVPixelBufferGetBytesPerRow(frame)
    let base = try #require(CVPixelBufferGetBaseAddress(frame)).assumingMemoryBound(to: UInt8.self)
    for row in 0..<4 {
        for column in 0..<8 {
            let pixel = base + row * rowBytes + column * 4
            pixel[0] = 0; pixel[1] = 0; pixel[2] = 255; pixel[3] = 255 // BGRA
        }
    }
    CVPixelBufferUnlockBaseAddress(frame, [])
    #expect(video.copy(frame))

    // Read the private texture back through a shared copy.
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm_srgb, width: 8, height: 4, mipmapped: false)
    descriptor.storageMode = .shared
    let readable = try #require(device.makeTexture(descriptor: descriptor))
    let queue = try #require(device.makeCommandQueue())
    let commandBuffer = try #require(queue.makeCommandBuffer())
    let blit = try #require(commandBuffer.makeBlitCommandEncoder())
    blit.copy(from: video.texture, to: readable)
    blit.endEncoding()
    commandBuffer.commit()
    commandBuffer.waitUntilCompleted()
    var pixel = SIMD4<UInt8>.zero
    readable.getBytes(&pixel, bytesPerRow: 8 * 4, from: MTLRegionMake2D(3, 2, 1, 1), mipmapLevel: 0)
    #expect(pixel == SIMD4(0, 0, 255, 255))
}
