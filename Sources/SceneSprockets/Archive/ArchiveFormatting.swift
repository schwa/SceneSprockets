import Foundation

// Readable scene.json (#159): simple enums as strings, number arrays on one line. Older archives wrote enums as
// synthesized objects ({"directional": {}}); those still read.

// Encodes as the raw value; decodes the raw value or the old synthesized object form.
enum ArchiveStringEnum {
    static func encode<Value: RawRepresentable<String>>(_ value: Value, to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value.rawValue)
    }

    static func decode<Value: RawRepresentable<String>>(_ type: Value.Type, from decoder: Decoder) throws -> Value {
        let name: String
        if let string = try? decoder.singleValueContainer().decode(String.self) {
            name = string
        } else {
            let container = try decoder.container(keyedBy: ArchiveAnyKey.self)
            guard let key = container.allKeys.first else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Empty enum object"))
            }
            name = key.stringValue
        }
        guard let value = Value(rawValue: name) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown \(Value.self) \"\(name)\""))
        }
        return value
    }
}

struct ArchiveAnyKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }

    init(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue: Int) {
        nil
    }
}

extension Light.LightType {
    public func encode(to encoder: Encoder) throws {
        try ArchiveStringEnum.encode(self, to: encoder)
    }

    public init(from decoder: Decoder) throws {
        self = try ArchiveStringEnum.decode(Self.self, from: decoder)
    }
}

extension MaterialRenderState.BlendMode {
    public func encode(to encoder: Encoder) throws {
        try ArchiveStringEnum.encode(self, to: encoder)
    }

    public init(from decoder: Decoder) throws {
        self = try ArchiveStringEnum.decode(Self.self, from: decoder)
    }
}

// `.none` is a string; cases with values keep the synthesized object form ({"color": {"_0": [...]}}).
extension SceneGraph.Environment.Background: Codable {
    enum ArchiveKeys: String, CodingKey {
        case none, color, environment, gradient
    }

    enum ValueKeys: String, CodingKey {
        case value = "_0", blur
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .none:
            var container = encoder.singleValueContainer()
            try container.encode("none")
        case let .color(color):
            var container = encoder.container(keyedBy: ArchiveKeys.self)
            var values = container.nestedContainer(keyedBy: ValueKeys.self, forKey: .color)
            try values.encode(color, forKey: .value)
        case let .environment(blur):
            var container = encoder.container(keyedBy: ArchiveKeys.self)
            var values = container.nestedContainer(keyedBy: ValueKeys.self, forKey: .environment)
            try values.encode(blur, forKey: .blur)
        case let .gradient(gradient):
            var container = encoder.container(keyedBy: ArchiveKeys.self)
            try container.encode(gradient, forKey: .gradient)
        }
    }

    public init(from decoder: Decoder) throws {
        if let string = try? decoder.singleValueContainer().decode(String.self) {
            guard string == "none" else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown background \"\(string)\""))
            }
            self = .none
            return
        }
        let container = try decoder.container(keyedBy: ArchiveKeys.self)
        if container.contains(.none) {
            self = .none
        } else if container.contains(.color) {
            self = .color(try container.nestedContainer(keyedBy: ValueKeys.self, forKey: .color).decode(SIMD4<Float>.self, forKey: .value))
        } else if container.contains(.environment) {
            self = .environment(blur: try container.nestedContainer(keyedBy: ValueKeys.self, forKey: .environment).decodeIfPresent(Float.self, forKey: .blur) ?? 0)
        } else if container.contains(.gradient) {
            self = .gradient(try container.decode(SceneGraph.Environment.SkyGradient.self, forKey: .gradient))
        } else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown background"))
        }
    }
}

enum ArchiveFormatting {
    // Puts arrays of numbers (and the "inf"/"nan" strings non-finite floats become) on one line.
    static func compactNumberArrays(_ json: String) -> String {
        let number = #"(?:-?\d[\d.eE+\-]*|"-?inf"|"nan")"#
        guard let expression = try? NSRegularExpression(pattern: #"\[\s*("# + number + #"(?:\s*,\s*"# + number + #")*)\s*\]"#) else {
            return json
        }
        let source = json as NSString
        var result = ""
        var location = 0
        for match in expression.matches(in: json, range: NSRange(location: 0, length: source.length)) {
            result += source.substring(with: NSRange(location: location, length: match.range.location - location))
            let items = source.substring(with: match.range(at: 1)).components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            result += "[" + items.joined(separator: ", ") + "]"
            location = match.range.location + match.range.length
        }
        result += source.substring(from: location)
        return result
    }
}
