import simd

extension SceneGraph {
    /// A smooth curve through points (Catmull-Rom), for paths that cameras and objects follow (#407).
    ///
    /// `t` runs from 0 at the first point to 1 at the end, and is spread by distance, so equal steps of `t` cover equal
    /// lengths of curve. Points are in whatever space the caller uses; ``Action/follow(_:duration:orientsToPath:)``
    /// takes them in the moving node's parent space.
    public struct Spline: Sendable, Equatable, Codable {
        /// The points the curve passes through.
        public let points: [SIMD3<Float>]
        /// Whether the curve continues from the last point back to the first.
        public let isClosed: Bool
        // Cumulative curve length at each sample, for mapping distance to the curve parameter.
        private let lengths: [Float]

        private static let samplesPerSegment = 32

        public init(points: [SIMD3<Float>], isClosed: Bool = false) {
            self.points = points
            self.isClosed = isClosed
            var lengths: [Float] = [0]
            let samples = Self.segmentCount(points: points, isClosed: isClosed) * Self.samplesPerSegment
            if samples > 0 {
                var previous = Self.curvePoint(points: points, isClosed: isClosed, parameter: 0)
                for index in 1...samples {
                    let point = Self.curvePoint(points: points, isClosed: isClosed, parameter: Float(index) / Float(samples))
                    lengths.append(lengths[lengths.count - 1] + simd_distance(previous, point))
                    previous = point
                }
            }
            self.lengths = lengths
        }

        /// The curve's length.
        public var length: Float {
            lengths.last ?? 0
        }

        /// The same curve, run from end to start.
        public var reversed: Self {
            Self(points: points.reversed(), isClosed: isClosed)
        }

        /// The point at `t` (clamped to 0...1, or wrapped for a closed curve), spread by distance along the curve.
        public func position(at t: Float) -> SIMD3<Float> {
            Self.curvePoint(points: points, isClosed: isClosed, parameter: parameter(at: t))
        }

        /// The unit direction of travel at `t`; zero if the curve has no length.
        public func tangent(at t: Float) -> SIMD3<Float> {
            let step: Float = 1e-3
            let delta = position(at: min(t + step, isClosed ? t + step : 1)) - position(at: max(t - step, isClosed ? t - step : 0))
            return simd_length(delta) > 1e-8 ? simd_normalize(delta) : .zero
        }

        // The uniform curve parameter (0...1 over all segments) that is `t` of the length along.
        private func parameter(at t: Float) -> Float {
            let t = isClosed ? t - floor(t) : min(max(t, 0), 1)
            guard length > 0, lengths.count > 1 else {
                return t
            }
            if isClosed, t == 0 {
                return 0
            }
            let target = t * length
            // The first sample at or past the target length.
            var low = 0
            var high = lengths.count - 1
            while low < high {
                let middle = (low + high) / 2
                if lengths[middle] < target {
                    low = middle + 1
                } else {
                    high = middle
                }
            }
            let upper = max(low, 1)
            let span = lengths[upper] - lengths[upper - 1]
            let fraction = span > 0 ? (target - lengths[upper - 1]) / span : 0
            return (Float(upper - 1) + fraction) / Float(lengths.count - 1)
        }

        private static func segmentCount(points: [SIMD3<Float>], isClosed: Bool) -> Int {
            guard points.count > 1 else {
                return 0
            }
            return isClosed ? points.count : points.count - 1
        }

        // Uniform Catmull-Rom through `points`; `parameter` runs 0...1 over all segments. Open curves repeat their end
        // points so the curve starts and ends on them.
        private static func curvePoint(points: [SIMD3<Float>], isClosed: Bool, parameter: Float) -> SIMD3<Float> {
            guard let first = points.first else {
                return .zero
            }
            let segments = segmentCount(points: points, isClosed: isClosed)
            guard segments > 0 else {
                return first
            }
            let scaled = min(max(parameter, 0), 1) * Float(segments)
            let segment = min(Int(scaled), segments - 1)
            let u = scaled - Float(segment)
            func point(_ index: Int) -> SIMD3<Float> {
                if isClosed {
                    return points[((index % points.count) + points.count) % points.count]
                }
                return points[min(max(index, 0), points.count - 1)]
            }
            let (p0, p1, p2, p3) = (point(segment - 1), point(segment), point(segment + 1), point(segment + 2))
            let u2 = u * u
            let u3 = u2 * u
            return 0.5 * ((2 * p1) + (p2 - p0) * u + (2 * p0 - 5 * p1 + 4 * p2 - p3) * u2 + (3 * p1 - p0 - 3 * p2 + p3) * u3)
        }

        public static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.points == rhs.points && lhs.isClosed == rhs.isClosed
        }

        enum CodingKeys: String, CodingKey {
            case points, isClosed
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.init(points: try container.decode([SIMD3<Float>].self, forKey: .points), isClosed: try container.decodeIfPresent(Bool.self, forKey: .isClosed) ?? false)
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(points, forKey: .points)
            try container.encode(isClosed, forKey: .isClosed)
        }
    }
}
