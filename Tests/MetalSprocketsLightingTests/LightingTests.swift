import Foundation
import Metal
import MetalSprocketsLighting
import simd
import Testing

// Compiles the lighting headers at runtime and runs their functions in a kernel, so tests need no shader in the package.
struct LightingTests {
    private static let kernels = """
    using namespace metal;

    kernel void sample_lights(
        constant LightingLight *lights [[buffer(0)]],
        constant float3 *positions [[buffer(1)]],
        device float3 *toLight [[buffer(2)]],
        device float3 *radiance [[buffer(3)]],
        uint index [[thread_position_in_grid]]
    ) {
        const Lighting::LightSample sample = Lighting::sample(lights[index], positions[index]);
        toLight[index] = sample.toLight;
        radiance[index] = sample.radiance;
    }

    kernel void shadow_lights(
        constant LightingLight *lights [[buffer(0)]],
        constant float3 *positions [[buffer(1)]],
        constant LightingShadowUniforms &uniforms [[buffer(2)]],
        device float3 *shadowing [[buffer(3)]],
        depth2d_array<float> shadowMap [[texture(0)]],
        sampler shadowSampler [[sampler(0)]],
        uint index [[thread_position_in_grid]]
    ) {
        shadowing[index] = Lighting::shadow(lights[index], positions[index], uniforms, shadowMap, shadowSampler);
    }

    kernel void tone_map(
        constant float3 *colors [[buffer(0)]],
        constant int *modes [[buffer(1)]],
        device float3 *output [[buffer(2)]],
        uint index [[thread_position_in_grid]]
    ) {
        output[index] = Lighting::toneMap(colors[index], LightingShaderToneMapping(modes[index]));
    }
    """

    private let device: any MTLDevice
    private let queue: any MTLCommandQueue
    private let library: any MTLLibrary

    init() throws {
        device = try #require(MTLCreateSystemDefaultDevice())
        queue = try #require(device.makeCommandQueue())
        let include = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Sources/MetalSprocketsLightingShaders/include")
        let headers = try ["MetalSprocketsLightingTypes.h", "MetalSprocketsLighting.h", "MetalSprocketsLightingToneMapping.h"].map { name in
            try String(contentsOf: include.appending(path: name), encoding: .utf8)
                .split(separator: "\n", omittingEmptySubsequences: false)
                .filter { !$0.hasPrefix("#include \"") && !$0.hasPrefix("#pragma once") }
                .joined(separator: "\n")
        }
        library = try device.makeLibrary(source: headers.joined(separator: "\n") + Self.kernels, options: nil)
    }

    private func buffer<T>(_ values: [T]) throws -> any MTLBuffer {
        let buffer = values.withUnsafeBytes { bytes in
            // swiftlint:disable:next force_unwrapping - the test arrays are never empty
            device.makeBuffer(bytes: bytes.baseAddress!, length: bytes.count, options: .storageModeShared)
        }
        return try #require(buffer)
    }

    private func run(_ name: String, count: Int, encode: (any MTLComputeCommandEncoder) -> Void) throws {
        let pipeline = try device.makeComputePipelineState(function: try #require(library.makeFunction(name: name)))
        let commandBuffer = try #require(queue.makeCommandBuffer())
        let encoder = try #require(commandBuffer.makeComputeCommandEncoder())
        encoder.setComputePipelineState(pipeline)
        encode(encoder)
        encoder.dispatchThreads(MTLSize(width: count, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: count, height: 1, depth: 1))
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }

    private func directional(shadowSlices: Range<Int32> = 0 ..< 0) -> LightingLight {
        var light = LightingLight.directional(direction: [0, -2, 0], color: [1, 0.5, 0.25], intensity: 2)
        light.shadowSliceStart = shadowSlices.lowerBound
        light.shadowSliceCount = Int32(shadowSlices.count)
        return light
    }

    @Test func toneMappingOperators() throws {
        let cases: [(LightingToneMapping, SIMD3<Float>, SIMD3<Float>)] = [
            (.linear, [2, 0.5, -1], [1, 0.5, 0]),
            (.reinhard, [1, 3, 0], [0.5, 0.75, 0]),
            (.none, [2, 0.5, -1], [2, 0.5, 0]),
            // Below the compression start, PBR Neutral only removes its small black offset.
            (.pbrNeutral, [0.5, 0.5, 0.5], [0.46, 0.46, 0.46])
        ]
        let colorBuffer = try buffer(cases.map(\.1))
        let modeBuffer = try buffer(cases.map { Int32($0.0.shaderValue.rawValue) })
        let output = try #require(device.makeBuffer(length: MemoryLayout<SIMD3<Float>>.stride * cases.count, options: .storageModeShared))
        try run("tone_map", count: cases.count) { encoder in
            encoder.setBuffer(colorBuffer, offset: 0, index: 0)
            encoder.setBuffer(modeBuffer, offset: 0, index: 1)
            encoder.setBuffer(output, offset: 0, index: 2)
        }
        let results = UnsafeBufferPointer(start: output.contents().assumingMemoryBound(to: SIMD3<Float>.self), count: cases.count)
        for (index, (mode, _, expected)) in cases.enumerated() {
            #expect(simd_distance(results[index], expected) < 1e-3, "\(mode): \(results[index])")
        }
    }

    // Same layout as MetalSprocketsPBR's PBRLight and PBRShadowUniforms, so renderers can share buffers.
    @Test func layoutsMatchPBR() {
        #expect(MemoryLayout<LightingLight>.size == 96)
        #expect(MemoryLayout<LightingLight>.stride == 96)
        // A matrix and a cascade float4 per slice (#88), then the scalars.
        #expect(MemoryLayout<LightingShadowUniforms>.offset(of: \.mapSize) == 80 * Int(kLightingMaxShadowSliceCount))
        #expect(MemoryLayout<LightingShadowUniforms>.offset(of: \.color) == 80 * Int(kLightingMaxShadowSliceCount) + 16)
    }

    @Test func samplesFollowKHRLightsPunctual() throws {
        let color: SIMD3<Float> = [1, 0.5, 0.25]
        let spot = LightingLight.spot(position: [0, 2, 0], direction: [0, -1, 0], color: color, intensity: 2, innerConeAngle: 0.1, outerConeAngle: 0.5)
        let lights = [
            directional(),
            .point(position: [0, 2, 0], color: color, intensity: 2),
            .point(position: [0, 2, 0], color: color, intensity: 2, range: 4),
            .point(position: [0, 5, 0], color: color, intensity: 2, range: 4),
            spot,
            spot
        ]
        // The last spot is lit from 45 degrees off its axis, outside the outer cone.
        let positions: [SIMD3<Float>] = [.zero, .zero, .zero, .zero, .zero, [2, 0, 0]]
        let toLight = try #require(device.makeBuffer(length: MemoryLayout<SIMD3<Float>>.stride * lights.count, options: .storageModeShared))
        let radiance = try #require(device.makeBuffer(length: MemoryLayout<SIMD3<Float>>.stride * lights.count, options: .storageModeShared))
        let lightBuffer = try buffer(lights)
        let positionBuffer = try buffer(positions)
        try run("sample_lights", count: lights.count) { encoder in
            encoder.setBuffer(lightBuffer, offset: 0, index: 0)
            encoder.setBuffer(positionBuffer, offset: 0, index: 1)
            encoder.setBuffer(toLight, offset: 0, index: 2)
            encoder.setBuffer(radiance, offset: 0, index: 3)
        }
        let directions = Array(UnsafeBufferPointer(start: toLight.contents().assumingMemoryBound(to: SIMD3<Float>.self), count: lights.count))
        let radiances = Array(UnsafeBufferPointer(start: radiance.contents().assumingMemoryBound(to: SIMD3<Float>.self), count: lights.count))
        let full = color * 2
        func close(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Bool { simd_distance(a, b) < 1e-4 }

        #expect(close(directions[0], [0, 1, 0]))
        #expect(close(radiances[0], full))
        // Inverse square at distance 2.
        #expect(close(directions[1], [0, 1, 0]))
        #expect(close(radiances[1], full / 4))
        // (1 - (2/4)^4) / 4.
        #expect(close(radiances[2], full * (1 - 1.0 / 16) / 4))
        // Beyond range.
        #expect(close(radiances[3], .zero))
        // On the spot's axis, inside the inner cone.
        #expect(close(radiances[4], full / 4))
        #expect(close(radiances[5], .zero))
    }

    // #86: SceneKit-style falloff: full up to the start distance, none past the end, (fraction)^exponent between.
    @Test func falloffAttenuationFollowsSceneKit() throws {
        func falloff(start: Float, end: Float, exponent: Float, distance: Float) -> LightingLight {
            var light = LightingLight.point(position: [0, distance, 0], color: [1, 1, 1], intensity: 1, range: end)
            light.attenuationStartDistance = start
            light.attenuationFalloffExponent = exponent
            return light
        }
        let lights = [
            falloff(start: 1, end: 5, exponent: 2, distance: 0.5),
            falloff(start: 1, end: 5, exponent: 2, distance: 3),
            falloff(start: 1, end: 5, exponent: 1, distance: 3),
            falloff(start: 1, end: 5, exponent: 2, distance: 6)
        ]
        let positions = [SIMD3<Float>](repeating: .zero, count: lights.count)
        let toLight = try #require(device.makeBuffer(length: MemoryLayout<SIMD3<Float>>.stride * lights.count, options: .storageModeShared))
        let radiance = try #require(device.makeBuffer(length: MemoryLayout<SIMD3<Float>>.stride * lights.count, options: .storageModeShared))
        let lightBuffer = try buffer(lights)
        let positionBuffer = try buffer(positions)
        try run("sample_lights", count: lights.count) { encoder in
            encoder.setBuffer(lightBuffer, offset: 0, index: 0)
            encoder.setBuffer(positionBuffer, offset: 0, index: 1)
            encoder.setBuffer(toLight, offset: 0, index: 2)
            encoder.setBuffer(radiance, offset: 0, index: 3)
        }
        let values = UnsafeBufferPointer(start: radiance.contents().assumingMemoryBound(to: SIMD3<Float>.self), count: lights.count).map(\.x)
        #expect(abs(values[0] - 1) < 1e-4)
        #expect(abs(values[1] - 0.25) < 1e-4)
        #expect(abs(values[2] - 0.5) < 1e-4)
        #expect(values[3] == 0)
    }

    @Test func shadowsMultiplySlicesAndTint() throws {
        // A 4x4 one-slice map at depth 0.5, seen straight down by an orthographic projection of x, z in -1...1.
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .depth32Float, width: 4, height: 4, mipmapped: false)
        descriptor.textureType = .type2DArray
        descriptor.usage = .shaderRead
        descriptor.storageMode = .private
        let shadowMap = try #require(device.makeTexture(descriptor: descriptor))
        let depths = try buffer([Float](repeating: 0.5, count: 16))
        let commandBuffer = try #require(queue.makeCommandBuffer())
        let blit = try #require(commandBuffer.makeBlitCommandEncoder())
        blit.copy(from: depths, sourceOffset: 0, sourceBytesPerRow: 16, sourceBytesPerImage: 64, sourceSize: MTLSize(width: 4, height: 4, depth: 1), to: shadowMap, destinationSlice: 0, destinationLevel: 0, destinationOrigin: MTLOrigin())
        blit.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.compareFunction = .lessEqual
        let sampler = try #require(device.makeSamplerState(descriptor: samplerDescriptor))

        // Clip x = world x, clip y = world z, depth = 0.5 - world y / 2: y > 0 is in front of the stored depth.
        let lookDown = simd_float4x4(columns: ([1, 0, 0, 0], [0, 0, -0.5, 0], [0, 1, 0, 0], [0, 0, 0.5, 1]))
        var uniforms = LightingShadowUniforms()
        uniforms.mapSize = 4
        uniforms.radius = 0
        uniforms.enabled = 1
        uniforms.intensity = 0.5
        uniforms.color = [0, 0, 1]
        withUnsafeMutableBytes(of: &uniforms.sliceViewProjections) { $0.storeBytes(of: lookDown, as: simd_float4x4.self) }

        let lights = [directional(shadowSlices: 0 ..< 1), directional(shadowSlices: 0 ..< 1), directional()]
        let positions: [SIMD3<Float>] = [[0, 0.5, 0], [0, -0.5, 0], [0, -0.5, 0]]
        let output = try #require(device.makeBuffer(length: MemoryLayout<SIMD3<Float>>.stride * lights.count, options: .storageModeShared))
        let lightBuffer = try buffer(lights)
        let positionBuffer = try buffer(positions)
        try run("shadow_lights", count: lights.count) { encoder in
            encoder.setBuffer(lightBuffer, offset: 0, index: 0)
            encoder.setBuffer(positionBuffer, offset: 0, index: 1)
            encoder.setBytes(&uniforms, length: MemoryLayout<LightingShadowUniforms>.size, index: 2)
            encoder.setBuffer(output, offset: 0, index: 3)
            encoder.setTexture(shadowMap, index: 0)
            encoder.setSamplerState(sampler, index: 0)
        }
        let shadowing = Array(UnsafeBufferPointer(start: output.contents().assumingMemoryBound(to: SIMD3<Float>.self), count: lights.count))
        // In front of the occluder: lit.
        #expect(shadowing[0] == [1, 1, 1])
        // Behind it: half way to the blue shadow color.
        #expect(simd_distance(shadowing[1], [0.5, 0.5, 1]) < 1e-4)
        // A light with no slices casts no shadow.
        #expect(shadowing[2] == [1, 1, 1])
    }
}
