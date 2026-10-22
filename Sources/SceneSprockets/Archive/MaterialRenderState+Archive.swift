import Metal

// Metal enums and option sets are stored as their raw values.
extension MaterialRenderState: Codable {
    enum ArchiveKeys: String, CodingKey {
        case blendMode, writesToDepthBuffer, readsFromDepthBuffer, colorWriteMask, fillMode
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: ArchiveKeys.self)
        try container.encode(blendMode, forKey: .blendMode)
        try container.encode(writesToDepthBuffer, forKey: .writesToDepthBuffer)
        try container.encode(readsFromDepthBuffer, forKey: .readsFromDepthBuffer)
        try container.encode(colorWriteMask.rawValue, forKey: .colorWriteMask)
        try container.encode(fillMode.rawValue, forKey: .fillMode)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: ArchiveKeys.self)
        self.init(
            blendMode: try container.decode(BlendMode.self, forKey: .blendMode),
            writesToDepthBuffer: try container.decode(Bool.self, forKey: .writesToDepthBuffer),
            readsFromDepthBuffer: try container.decode(Bool.self, forKey: .readsFromDepthBuffer),
            colorWriteMask: MTLColorWriteMask(rawValue: try container.decode(UInt.self, forKey: .colorWriteMask)),
            fillMode: MTLTriangleFillMode(rawValue: try container.decode(UInt.self, forKey: .fillMode)) ?? .fill
        )
    }
}
