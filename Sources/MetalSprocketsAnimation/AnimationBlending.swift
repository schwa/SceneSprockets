import simd

/// How a layer combines with the other layers.
public enum AnimationBlendMode: Sendable, Equatable {
    /// The layer blends with the other override layers by normalized weight.
    case override
    /// The layer adds the clip's offset from the rest pose, scaled by the weight, on top of the override layers.
    case additive
}

/// How an animated value blends and how an additive layer adds to it.
public enum AnimationValueKind: Sendable {
    /// A quaternion (x, y, z, w): blended by normalized linear interpolation, added by composing rotations.
    case rotation
    /// A scale: blended linearly, added by multiplying.
    case scale
    /// Anything else: blended and added linearly.
    case linear
}

/// The blending shared by glTF assets and scene graphs (#589). `Key` names one animated value, such as a node's
/// rotation.
public enum AnimationBlending {
    /// Blends override layers by normalized weight. Where the layers that animate a value weigh less than the total,
    /// its rest value (when `rest` has one) fills the rest of the weight.
    public static func blendedValues<Key: Hashable>(
        _ layers: [(weight: Float, values: [Key: [Float]])],
        rest: (Key) -> [Float]?,
        kind: (Key) -> AnimationValueKind
    ) -> [Key: [Float]] {
        let totalWeight = layers.reduce(0) { $0 + $1.weight }
        guard totalWeight > 0 else {
            return [:]
        }
        var contributions: [Key: [(weight: Float, value: [Float])]] = [:]
        for layer in layers {
            for (key, value) in layer.values {
                contributions[key, default: []].append((layer.weight / totalWeight, value))
            }
        }
        var result: [Key: [Float]] = [:]
        for (key, list) in contributions {
            var list = list
            let covered = list.reduce(0) { $0 + $1.weight }
            if covered < 1 - 1e-6, let restValue = rest(key) {
                list.append((1 - covered, restValue))
            }
            result[key] = blend(list, isRotation: kind(key) == .rotation)
        }
        return result
    }

    /// Adds how far `sampled` moves each value from its rest value, scaled by `weight`, to `values`. Values without a
    /// rest value are skipped.
    public static func addDeltas<Key: Hashable>(
        _ sampled: [Key: [Float]],
        weight: Float,
        to values: inout [Key: [Float]],
        rest: (Key) -> [Float]?,
        kind: (Key) -> AnimationValueKind
    ) {
        for (key, sample) in sampled {
            guard let restValue = rest(key) else {
                continue
            }
            let base = values[key] ?? restValue
            guard sample.count == restValue.count, base.count == restValue.count else {
                continue
            }
            switch kind(key) {
            case .rotation where restValue.count == 4:
                let restRotation = simd_quatf(vector: SIMD4(restValue[0], restValue[1], restValue[2], restValue[3]))
                let sampledRotation = simd_quatf(vector: SIMD4(sample[0], sample[1], sample[2], sample[3]))
                let baseRotation = simd_quatf(vector: SIMD4(base[0], base[1], base[2], base[3]))
                let delta = simd_slerp(simd_quatf(ix: 0, iy: 0, iz: 0, r: 1), restRotation.inverse * sampledRotation, weight)
                let result = simd_normalize(baseRotation * delta).vector
                values[key] = [result.x, result.y, result.z, result.w]
            case .scale where restValue.count == 3:
                values[key] = (0..<3).map { index in
                    restValue[index] == 0 ? base[index] : base[index] * pow(sample[index] / restValue[index], weight)
                }
            default:
                values[key] = (0..<restValue.count).map { base[$0] + (sample[$0] - restValue[$0]) * weight }
            }
        }
    }

    /// The weighted average of `list`. Rotations use normalized linear interpolation on the first value's side.
    public static func blend(_ list: [(weight: Float, value: [Float])], isRotation: Bool) -> [Float] {
        guard list.count > 1 else {
            return list.first?.value ?? []
        }
        let count = list.map(\.value.count).min() ?? 0
        let reference = list[0].value
        var result = [Float](repeating: 0, count: count)
        var totalWeight: Float = 0
        for (weight, value) in list {
            // q and -q are the same rotation: blend each on the reference's side.
            var sign: Float = 1
            if isRotation {
                let dot = zip(reference.prefix(count), value.prefix(count)).reduce(0) { $0 + $1.0 * $1.1 }
                sign = dot < 0 ? -1 : 1
            }
            for index in 0..<count {
                result[index] += value[index] * weight * sign
            }
            totalWeight += weight
        }
        if isRotation {
            let length = sqrt(result.reduce(0) { $0 + $1 * $1 })
            return length > 0 ? result.map { $0 / length } : reference
        }
        return totalWeight > 0 ? result.map { $0 / totalWeight } : reference
    }
}
