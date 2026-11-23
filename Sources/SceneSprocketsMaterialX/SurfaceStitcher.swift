import Foundation
import MaterialX
import MaterialXMetal
import Metal
import MetalKit
import MetalSprockets
import MetalSprocketsPBR
import Synchronization

// Compiles a document's surface shaders into PBR surface functions with MetalSprocketsMaterialX (#667), so node
// graphs the CPU conversion cannot fold run per pixel.
struct SurfaceStitcher {
    enum Failure: Error, CustomStringConvertible {
        case noShader(String)
        case bufferCreationFailed

        var description: String {
            switch self {
            case let .noShader(name): "no surface shader \(name)"
            case .bufferCreationFailed: "could not create a buffer"
            }
        }
    }

    let document: MaterialX.MaterialXDocument
    let baseURL: URL
    let device: MTLDevice

    // `base` with a surface function for shader `shader`. Its uniforms, textures and render state are kept: the
    // function starts from its factors, and the alpha mode and transmission decide how it is drawn.
    func material(shader name: String, replacing base: PBRMaterial) throws -> PBRMaterial {
        guard let shader = document.nodes.first(where: { $0.name == name }) else {
            throw Failure.noShader(name)
        }
        let stitcher = try GraphStitcher(nodeLibrary: Self.nodeLibrary(device: device), standardLibrary: StandardLibrary.shared.merging([document]))
        let graph = try stitcher.stitchSurface(shader, in: document, functionName: "materialx_\(Self.identifier(name))")
        let parameterData = graph.parameterData.isEmpty ? [SIMD4<Float>.zero] : graph.parameterData
        guard let parameters = device.makeBuffer(bytes: parameterData, length: MemoryLayout<SIMD4<Float>>.stride * parameterData.count) else {
            throw Failure.bufferCreationFailed
        }
        parameters.label = "MaterialX \(name) Parameters"
        let slots = try graph.textures.sorted { $0.slot < $1.slot }.map { binding -> (texture: MTLTexture, sampler: MTLSamplerState)? in
            guard !binding.file.isEmpty else {
                return nil
            }
            let url = binding.file.hasPrefix("/") ? URL(fileURLWithPath: binding.file) : baseURL.appending(path: binding.file)
            // Colors are converted from their colorspace in the graph, so the texture is read as stored.
            let texture = try MTKTextureLoader(device: device).newTexture(URL: url, options: [
                .SRGB: false,
                .generateMipmaps: true,
                .allocateMipmaps: true,
                .textureStorageMode: MTLStorageMode.private.rawValue
            ])
            guard let sampler = device.makeSamplerState(descriptor: binding.samplerDescriptor) else {
                throw Failure.bufferCreationFailed
            }
            return (texture, sampler)
        }
        let surface = PBRMaterial.SurfaceFunction(
            function: try VisibleFunction(library: graph.library, name: graph.functionName),
            parameters: parameters,
            textureTable: try StitchedGraph.makeTextureTable(slots, device: device),
            textures: slots.compactMap { $0?.texture }
        )
        return PBRMaterial(
            name: base.name,
            uniforms: base.uniforms,
            doubleSided: base.doubleSided,
            renderState: base.renderState,
            textureTransforms: base.textureTransforms,
            textureBindings: base.textureBindings,
            surfaceFunction: surface
        )
    }

    // Function names must be Metal identifiers.
    static func identifier(_ name: String) -> String {
        String(name.map { $0.isLetter || $0.isNumber ? $0 : "_" })
    }

    // One node library per device: it loads the Metal node functions and caches stitched libraries.
    private static let libraries = Mutex<[ObjectIdentifier: MetalNodeLibrary]>([:])

    static func nodeLibrary(device: MTLDevice) throws -> MetalNodeLibrary {
        if let library = libraries.withLock({ $0[ObjectIdentifier(device)] }) {
            return library
        }
        let library = try MetalNodeLibrary(device: device)
        return libraries.withLock { libraries in
            if let raced = libraries[ObjectIdentifier(device)] {
                return raced
            }
            libraries[ObjectIdentifier(device)] = library
            return library
        }
    }
}
