import Foundation
import Metal
import MetalSprocketsSupport

/// Automatic exposure, like a camera's auto exposure (#508): each frame meters the drawn geometry and moves the exposure
/// so its average luminance approaches ``targetLuminance``. The result multiplies ``SceneGraph/Environment/exposure``.
///
/// Keep one instance across frames and pass it to SceneView's `sceneAutoExposure(_:)` or
/// `SceneGraphElement(autoExposure:)`. Metering reads the view's color and depth, so it needs the same texture usage as
/// ``Shadows`` (`Shadows.requiredColorUsage`). The background is not metered.
///
/// The frame is metered after tone mapping and read back a few frames later, so the exposure follows the scene with a
/// short delay.
///
/// You can change the settings on one thread while a view draws with the object on its render thread.
public final class AutoExposure: @unchecked Sendable {
    struct Settings {
        var targetLuminance: Float
        var adaptationSpeed: Float
        var range: ClosedRange<Float>
        var exposure: Float = 1
        var lastUpdate: Date?
        var lastSubmission: UInt64?
    }

    private let lock = NSLock()
    private var settings: Settings
    // One result buffer per frame in flight, read back when its slot comes round again.
    private var buffers: [MTLBuffer] = []
    // The exposure each slot's frame was drawn with.
    private var slotExposures: [Float] = Array(repeating: 1, count: frameSlotCount)

    /// The linear luminance, from 0 to 1, that the metered geometry averages to (geometric mean).
    public var targetLuminance: Float {
        get { lock.withLock { settings.targetLuminance } }
        set { lock.withLock { settings.targetLuminance = newValue } }
    }

    /// How fast the exposure moves, in stops per second.
    public var adaptationSpeed: Float {
        get { lock.withLock { settings.adaptationSpeed } }
        set { lock.withLock { settings.adaptationSpeed = newValue } }
    }

    /// The smallest and largest exposure multiplier.
    public var range: ClosedRange<Float> {
        get { lock.withLock { settings.range } }
        set { lock.withLock { settings.range = newValue } }
    }

    /// The current exposure multiplier.
    public var exposure: Float {
        lock.withLock { settings.exposure }
    }

    /// Creates automatic exposure.
    ///
    /// - Parameters:
    ///   - targetLuminance: The average linear luminance to aim for.
    ///   - adaptationSpeed: How fast the exposure moves, in stops per second.
    ///   - range: The smallest and largest exposure multiplier.
    public init(targetLuminance: Float = 0.18, adaptationSpeed: Float = 2, range: ClosedRange<Float> = 1.0 / 16 ... 16) {
        settings = Settings(targetLuminance: targetLuminance, adaptationSpeed: adaptationSpeed, range: range)
    }

    static let frameSlotCount = 3

    // Reads the metering result that last used this submission's slot, moves the exposure towards the target, and
    // returns the new exposure with the buffer this frame meters into. Runs once per submission.
    func update(submissionIndex: UInt64, device: MTLDevice, now: Date = Date()) throws -> (exposure: Float, buffer: MTLBuffer) {
        try lock.withLock {
            if buffers.isEmpty {
                buffers = try (0..<Self.frameSlotCount).map { slot in
                    let buffer = try device.makeBuffer(length: MemoryLayout<SIMD2<Float>>.stride, options: .storageModeShared)
                        .orThrow(.resourceCreationFailure("Auto exposure metering buffer"))
                    buffer.label = "Auto Exposure Metering [\(slot)]"
                    buffer.contents().storeBytes(of: SIMD2<Float>.zero, as: SIMD2<Float>.self)
                    return buffer
                }
            }
            let slot = Int(submissionIndex % UInt64(Self.frameSlotCount))
            let buffer = buffers[slot]
            guard settings.lastSubmission != submissionIndex else {
                return (settings.exposure, buffer)
            }
            settings.lastSubmission = submissionIndex
            let elapsed = settings.lastUpdate.map { Float(now.timeIntervalSince($0)) } ?? 0
            settings.lastUpdate = now
            let metered = buffer.contents().load(as: SIMD2<Float>.self)
            // y is the number of metered samples; 0 when nothing but background was drawn or the slot is new.
            if metered.y > 0 {
                settings.exposure = Self.adapted(exposure: settings.exposure, meteredLog2Luminance: metered.x, meteredExposure: slotExposures[slot], settings: settings, elapsed: elapsed)
            }
            slotExposures[slot] = settings.exposure
            buffer.contents().storeBytes(of: SIMD2<Float>.zero, as: SIMD2<Float>.self)
            return (settings.exposure, buffer)
        }
    }

    // One step towards the target, at most `adaptationSpeed * elapsed` stops. The metered frame was drawn a few frames
    // ago with `meteredExposure`; the change since then is taken off the error, or fast adaptation overshoots and
    // oscillates (#606).
    static func adapted(exposure: Float, meteredLog2Luminance: Float, meteredExposure: Float, settings: Settings, elapsed: Float) -> Float {
        let current = meteredLog2Luminance + log2(exposure / max(meteredExposure, 1e-6))
        let error = log2(max(settings.targetLuminance, 1e-4)) - current
        let limit = max(settings.adaptationSpeed * max(elapsed, 0), 0)
        let step = min(max(error, -limit), limit)
        return min(max(exposure * pow(2, step), settings.range.lowerBound), settings.range.upperBound)
    }
}
