import Foundation
import Metal
import MetalSprockets
import SceneSprockets
import simd

// Saved by SceneArchive (#160) as references to its shaders: a library name from SceneArchive.shaderLibraries
// (the sample shaders are always available) and the function names. Specialized functions (function constants) and
// samplers are not saved; they are skipped with a warning. Buffers are saved as their bytes when the CPU can read
// them.
extension ShaderMaterial: ArchivableMaterial {
    public static let archiveTypeName = "shader"

    enum ArchiveKeys: String, CodingKey {
        case library, vertexFunction, fragmentFunction, parameters, isTransparent, renderState
    }

    enum ParameterKeys: String, CodingKey {
        case name, float, float2, float3, float4, float4x4, texture, buffer
    }

    public func archiveProblem(context: SceneArchiveContext) -> String? {
        let vertex = vertexShader.reference, fragment = fragmentShader.reference
        if vertex.library !== fragment.library {
            return "ShaderMaterial functions come from different libraries"
        }
        if Self.libraryName(for: vertex.library, context: context) == nil {
            return "ShaderMaterial library \(vertex.library.label.map { "\"\($0)\"" } ?? "") is not in SceneArchive.shaderLibraries"
        }
        if !vertex.constants.isEmpty || !fragment.constants.isEmpty || vertex.specializedName != nil || fragment.specializedName != nil {
            return "specialized ShaderMaterial functions (function constants) cannot be saved"
        }
        return nil
    }

    public func encode(to encoder: Encoder) throws {
        let context = try encoder.sceneArchive
        if let problem = archiveProblem(context: context) {
            throw EncodingError.invalidValue(self, .init(codingPath: encoder.codingPath, debugDescription: problem))
        }
        let vertex = vertexShader.reference, fragment = fragmentShader.reference
        let library = Self.libraryName(for: vertex.library, context: context) ?? ""
        var container = encoder.container(keyedBy: ArchiveKeys.self)
        try container.encode(library, forKey: .library)
        try container.encode(vertex.name, forKey: .vertexFunction)
        try container.encode(fragment.name, forKey: .fragmentFunction)
        try container.encode(alphaBlends, forKey: .isTransparent)
        try container.encode(renderState, forKey: .renderState)
        var list = container.nestedUnkeyedContainer(forKey: .parameters)
        for (name, value) in parameters.sorted(by: { $0.key < $1.key }) {
            var item = list.nestedContainer(keyedBy: ParameterKeys.self)
            try item.encode(name, forKey: .name)
            switch value {
            case .float(let value):
                try item.encode(value, forKey: .float)
            case .float2(let value):
                try item.encode(value, forKey: .float2)
            case .float3(let value):
                try item.encode(value, forKey: .float3)
            case .float4(let value):
                try item.encode(value, forKey: .float4)
            case .float4x4(let value):
                let columns = [value.columns.0, value.columns.1, value.columns.2, value.columns.3]
                try item.encode(columns.flatMap { [$0.x, $0.y, $0.z, $0.w] }, forKey: .float4x4)
            case .texture(let texture):
                try item.encode(try context.encode(texture: texture), forKey: .texture)
            case .buffer(let buffer):
                guard buffer.storageMode != .private else {
                    context.warn("ShaderMaterial parameter \"\(name)\": private buffer cannot be read; skipped")
                    continue
                }
                try item.encode(Data(bytes: buffer.contents(), count: buffer.length), forKey: .buffer)
            case .sampler:
                // Samplers cannot be read back (#180).
                context.warn("ShaderMaterial parameter \"\(name)\": sampler not saved")
            }
        }
    }

    public init(from decoder: Decoder) throws {
        let context = try decoder.sceneArchive
        let container = try decoder.container(keyedBy: ArchiveKeys.self)
        let libraryName = try container.decode(String.self, forKey: .library)
        guard let library = try Self.library(named: libraryName, context: context) else {
            throw DecodingError.dataCorruptedError(forKey: .library, in: container, debugDescription: "No shader library \"\(libraryName)\" in SceneArchive.shaderLibraries")
        }
        let vertex = try VertexShader(ShaderFunction(library: library, name: try container.decode(String.self, forKey: .vertexFunction), type: .vertex))
        let fragment = try FragmentShader(ShaderFunction(library: library, name: try container.decode(String.self, forKey: .fragmentFunction), type: .fragment))
        var parameters: [String: Value] = [:]
        var list = try container.nestedUnkeyedContainer(forKey: .parameters)
        while !list.isAtEnd {
            let item = try list.nestedContainer(keyedBy: ParameterKeys.self)
            let name = try item.decode(String.self, forKey: .name)
            if let value = try item.decodeIfPresent(Float.self, forKey: .float) {
                parameters[name] = .float(value)
            } else if let value = try item.decodeIfPresent(SIMD2<Float>.self, forKey: .float2) {
                parameters[name] = .float2(value)
            } else if let value = try item.decodeIfPresent(SIMD3<Float>.self, forKey: .float3) {
                parameters[name] = .float3(value)
            } else if let value = try item.decodeIfPresent(SIMD4<Float>.self, forKey: .float4) {
                parameters[name] = .float4(value)
            } else if let values = try item.decodeIfPresent([Float].self, forKey: .float4x4) {
                guard values.count == 16 else {
                    throw DecodingError.dataCorruptedError(forKey: .float4x4, in: item, debugDescription: "A float4x4 needs 16 values")
                }
                parameters[name] = .float4x4(simd_float4x4(columns: ([values[0], values[1], values[2], values[3]], [values[4], values[5], values[6], values[7]], [values[8], values[9], values[10], values[11]], [values[12], values[13], values[14], values[15]])))
            } else if let reference = try item.decodeIfPresent(SceneArchiveContext.TextureReference.self, forKey: .texture) {
                parameters[name] = .texture(try context.texture(for: reference))
            } else if let data = try item.decodeIfPresent(Data.self, forKey: .buffer) {
                guard let buffer = data.withUnsafeBytes({ bytes in bytes.baseAddress.flatMap { library.device.makeBuffer(bytes: $0, length: bytes.count, options: .storageModeShared) } }) else {
                    throw DecodingError.dataCorruptedError(forKey: .buffer, in: item, debugDescription: "Could not make a buffer for \"\(name)\"")
                }
                parameters[name] = .buffer(buffer)
            } else {
                context.warn("ShaderMaterial parameter \"\(name)\": no value; skipped")
            }
        }
        self.init(vertexShader: vertex, fragmentShader: fragment, parameters: parameters, isTransparent: try container.decode(Bool.self, forKey: .isTransparent), renderState: try container.decode(MaterialRenderState.self, forKey: .renderState))
    }

    private static func libraryName(for library: any MTLLibrary, context: SceneArchiveContext) -> String? {
        if let name = context.shaderLibraryName(for: library) {
            return name
        }
        let samples = try? sampleLibrary()
        return samples === library ? ShaderMaterialSampleLibrary.archiveName : nil
    }

    private static func library(named name: String, context: SceneArchiveContext) throws -> (any MTLLibrary)? {
        if let library = context.shaderLibrary(named: name) {
            return library
        }
        return name == ShaderMaterialSampleLibrary.archiveName ? try sampleLibrary() : nil
    }

    private static func sampleLibrary() throws -> any MTLLibrary {
        try ShaderMaterialSampleLibrary.shared().function(named: "vertex_main", type: VertexShader.self).reference.library
    }
}
