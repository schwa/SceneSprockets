import Foundation
import simd

/// Runs a scene graph's frame updates on the main actor and publishes snapshots for a renderer on another thread
/// (#391), like SceneKit's presentation tree.
///
/// Each step runs ``update``, advances actions and particles, applies constraints and publishes a
/// ``SceneGraph/presentation()``. A renderer on any thread draws the latest one with ``takePresentation()``. Edit the
/// scene graph only on the main actor. Meshes and materials in a snapshot are shared references: changing a material's
/// properties while another thread renders it is still a race.
@MainActor
public final class ScenePresenter {
    /// The scene this presenter updates.
    public let sceneGraph: SceneGraph
    /// False freezes scene time: actions, particles and constraints stop. Snapshots are still published.
    public var isPlaying = true
    /// Called first in every step with the scene time and the time since the last step, both 0-based and paused with
    /// ``isPlaying``. Make per-frame edits here.
    public var update: ((_ time: Float, _ deltaTime: Float) -> Void)?

    private let clock = SceneClock()
    private let shared = Shared()
    private var driver: Task<Void, Never>?

    /// Creates a presenter for a scene graph and publishes its first snapshot.
    public init(sceneGraph: SceneGraph) {
        self.sceneGraph = sceneGraph
        shared.publish(sceneGraph.presentation())
    }

    /// Steps once: runs ``update``, advances the scene and publishes a snapshot. `frameTime` is a clock in seconds.
    public func step(frameTime: Float) {
        let (time, deltaTime) = clock.advance(to: frameTime, isPaused: !isPlaying)
        update?(time, deltaTime)
        sceneGraph.advanceActions(by: deltaTime)
        sceneGraph.advanceParticles(by: deltaTime)
        sceneGraph.applyConstraints(pointOfView: shared.viewerTransform, deltaTime: deltaTime)
        shared.publish(sceneGraph.presentation())
    }

    /// Steps about `framesPerSecond` times a second on the main actor until ``stop()``.
    public func start(framesPerSecond: Double = 90) {
        guard driver == nil else {
            return
        }
        let start = ContinuousClock.now
        driver = Task { [weak self] in
            while !Task.isCancelled {
                let elapsed = ContinuousClock.now - start
                let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) * 1e-18
                self?.step(frameTime: Float(seconds))
                try? await Task.sleep(for: .seconds(1 / framesPerSecond))
            }
        }
    }

    /// Stops stepping.
    public func stop() {
        driver?.cancel()
        driver = nil
    }

    /// Returns the latest snapshot, from any thread. Its particle steps are handed out once: a snapshot taken again
    /// before the next step does not simulate particles again.
    nonisolated public func takePresentation() -> SceneGraph.Presentation {
        shared.take()
    }

    /// Returns the latest snapshot, from any thread, without taking its particle steps. For reading values such as
    /// bounds; draw with ``takePresentation()``.
    nonisolated public func peekPresentation() -> SceneGraph.Presentation {
        shared.peek()
    }

    /// Records the viewer's world transform, from any thread, for constraints such as billboards and look-at.
    nonisolated public func setViewerTransform(_ transform: simd_float4x4) {
        shared.setViewerTransform(transform)
    }

    // State shared with the rendering thread.
    private final class Shared: @unchecked Sendable {
        private let lock = NSLock()
        private var presentation: SceneGraph.Presentation?
        private var viewer = matrix_identity_float4x4

        func publish(_ presentation: SceneGraph.Presentation) {
            lock.withLock { self.presentation = presentation }
        }

        func peek() -> SceneGraph.Presentation {
            lock.withLock {
                guard let presentation else {
                    preconditionFailure("No published presentation")
                }
                return presentation
            }
        }

        func take() -> SceneGraph.Presentation {
            lock.withLock {
                // Set in init, so never nil.
                guard let current = presentation else {
                    preconditionFailure("No published presentation")
                }
                presentation = current.withParticleStepsTaken()
                return current
            }
        }

        var viewerTransform: simd_float4x4 {
            lock.withLock { viewer }
        }

        func setViewerTransform(_ transform: simd_float4x4) {
            lock.withLock { viewer = transform }
        }
    }
}

extension SceneGraph.Presentation {
    // A copy whose particle frames advance by nothing and restart nothing, for drawing the same snapshot again.
    func withParticleStepsTaken() -> Self {
        var copy = self
        copy.particleFrames = particleFrames.map { $0.withStepTaken() }
        return copy
    }
}

extension SceneParticleSystem.Frame {
    func withStepTaken() -> Self {
        Self(system: system, description: description, generation: generation, deltaTime: 0, placement: placement, isHidden: isHidden, restarts: false)
    }
}
