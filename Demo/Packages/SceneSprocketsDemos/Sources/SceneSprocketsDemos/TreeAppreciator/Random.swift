import simd

// Small seeded generator (mulberry32) so a seed always grows the same tree.
struct SeededRandom {
    private var state: UInt32

    init(seed: UInt32) {
        state = seed
    }

    init(_ string: String) {
        self.init(seed: fnv1a(string))
    }

    mutating func next() -> Float {
        state = state &+ 0x6D2B_79F5
        var t = (state ^ (state >> 15)) &* (1 | state)
        t = (t &+ ((t ^ (t >> 7)) &* (61 | t))) ^ t
        return Float(Double(t ^ (t >> 14)) / 4_294_967_296)
    }

    mutating func range(_ lower: Float, _ upper: Float) -> Float {
        lower + (upper - lower) * next()
    }

    mutating func pick<T>(_ array: [T]) -> T {
        array[min(Int(next() * Float(array.count)), array.count - 1)]
    }

    mutating func signed() -> Float {
        next() - 0.5
    }
}

func fnv1a(_ string: String) -> UInt32 {
    var hash: UInt32 = 2_166_136_261
    for byte in string.utf8 {
        hash ^= UInt32(byte)
        hash = hash &* 16_777_619
    }
    return hash
}

func mix(_ a: Float, _ b: Float, _ t: Float) -> Float {
    a + (b - a) * t
}

// sRGB hex to linear RGB, which is what the Blinn-Phong materials expect.
func linearColor(_ hex: UInt32) -> SIMD3<Float> {
    func channel(_ value: UInt32) -> Float {
        let c = Float(value & 0xFF) / 255
        return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }
    return [channel(hex >> 16), channel(hex >> 8), channel(hex)]
}

extension simd_float4x4 {
    func transformPoint(_ point: SIMD3<Float>) -> SIMD3<Float> {
        let result = self * SIMD4<Float>(point, 1)
        return [result.x, result.y, result.z]
    }
}
