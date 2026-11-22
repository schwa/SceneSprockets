import ArgumentParser
import Foundation
import MetalSprockets
import MetalSprocketsGLTF
import MetalSprocketsPBR
import simd

/// Times a fixed set of sample scenes, one per draw path, and compares them with this machine's recorded baseline.
struct GLTFBenchCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "bench",
        abstract: "Benchmark a fixed set of sample scenes against this machine's baseline.",
        discussion: "Run a Release build from the repository root. Baselines are per machine (Benchmarks/glTF/<model>.json); record one with --record. Exits with status 1 when a scene's median CPU or GPU time is slower than its baseline by more than the margin."
    )

    struct Scene {
        var name: String
        /// Relative to the models directory.
        var path: String
        var animation: Int?
        var orbit = true
        /// Draws a different KHR_materials_variants variant each frame (#608).
        var switchesVariants = false
        /// Draws the environment behind the scene (`render --background`).
        var showsBackground = false
        /// Overrides --width and --height, for GPU-bound sizes.
        var size: (width: Int, height: Int)?
    }

    private static let size4K = (width: 3_840, height: 2_160)

    static let scenes: [Scene] = [
        Scene(name: "ABeautifulGame", path: "ABeautifulGame/glTF-Binary/ABeautifulGame.glb"),
        Scene(name: "Sponza", path: "Sponza/glTF/Sponza.gltf"),
        Scene(name: "NodePerformanceTest", path: "NodePerformanceTest/glTF-Binary/NodePerformanceTest.glb"),
        Scene(name: "SimpleInstancing", path: "SimpleInstancing/glTF-Binary/SimpleInstancing.glb"),
        Scene(name: "BrainStem", path: "BrainStem/glTF-Binary/BrainStem.glb", animation: 0),
        Scene(name: "RecursiveSkeletons", path: "RecursiveSkeletons/glTF-Binary/RecursiveSkeletons.glb", animation: 0),
        Scene(name: "Fox", path: "Fox/glTF-Binary/Fox.glb", animation: 0),
        Scene(name: "AnimationPointerUVs", path: "AnimationPointerUVs/glTF-Binary/AnimationPointerUVs.glb", animation: 0),
        Scene(name: "AlphaBlendModeTest", path: "AlphaBlendModeTest/glTF-Binary/AlphaBlendModeTest.glb"),
        Scene(name: "TransmissionTest", path: "TransmissionTest/glTF-Binary/TransmissionTest.glb"),
        Scene(name: "CarConcept", path: "CarConcept/glTF-Binary/CarConcept.glb"),
        // #558: paths the scenes above miss.
        // Morph targets, animated.
        Scene(name: "MorphStressTest", path: "MorphStressTest/glTF-Binary/MorphStressTest.glb", animation: 0),
        // Material lobes that add shader cost.
        Scene(name: "ClearCoatCarPaint", path: "ClearCoatCarPaint/glTF-Binary/ClearCoatCarPaint.glb"),
        Scene(name: "SheenWoodLeatherSofa", path: "SheenWoodLeatherSofa/glTF-Binary/SheenWoodLeatherSofa.glb"),
        Scene(name: "DiffuseTransmissionPlant", path: "DiffuseTransmissionPlant/glTF-Binary/DiffuseTransmissionPlant.glb"),
        Scene(name: "IridescenceLamp", path: "IridescenceLamp/glTF-Binary/IridescenceLamp.glb"),
        Scene(name: "AnisotropyBarnLamp", path: "AnisotropyBarnLamp/glTF-Binary/AnisotropyBarnLamp.glb"),
        Scene(name: "DispersionTest", path: "DispersionTest/glTF-Binary/DispersionTest.glb"),
        // Point and line primitives.
        Scene(name: "MeshPrimitiveModes", path: "MeshPrimitiveModes/glTF/MeshPrimitiveModes.gltf"),
        // Many punctual lights.
        Scene(name: "LightsPunctualLamp", path: "LightsPunctualLamp/glTF-Binary/LightsPunctualLamp.glb"),
        // Many large textures and materials.
        Scene(name: "FlightHelmet", path: "FlightHelmet/glTF/FlightHelmet.gltf"),
        // #608: paths the scenes above still miss.
        // KHR_materials_variants switched every frame.
        Scene(name: "MaterialsVariantsShoe", path: "MaterialsVariantsShoe/glTF-Binary/MaterialsVariantsShoe.glb", switchesVariants: true),
        // KHR_node_visibility animated.
        Scene(name: "CubeVisibility", path: "CubeVisibility/glTF/CubeVisibility.gltf", animation: 0),
        // GPU-bound: 4K, the environment background and the transmission pre-pass.
        Scene(name: "Sponza-4K", path: "Sponza/glTF/Sponza.gltf", size: size4K),
        Scene(name: "TransmissionTest-4K-bg", path: "TransmissionTest/glTF-Binary/TransmissionTest.glb", showsBackground: true, size: size4K),
        Scene(name: "FlightHelmet-4K-bg", path: "FlightHelmet/glTF/FlightHelmet.gltf", showsBackground: true, size: size4K)
    ]

    struct Baseline: Codable {
        var machine: String
        var chip: String
        var recorded: Date
        var frames: Int
        var width: Int
        var height: Int
        var scenes: [String: FrameTimings]
        // Milliseconds to load each scene (GLTFAsset), fastest of the rounds. Nil in baselines from before #558.
        // swiftlint:disable:next discouraged_optional_collection - nil means the baseline predates load times
        var loadTimes: [String: Double]?
    }

    @Option(help: "glTF-Sample-Assets Models directory.")
    var models = ".sample-assets/Models"

    @Option(help: "Directory holding per-machine baselines.")
    var baselines = "Benchmarks/glTF"

    @Flag(help: "Write this machine's baseline instead of comparing.")
    var record = false

    @Option(help: "Frames timed per run, after 30 warm-up frames.")
    var frames = 60

    @Option(help: "Rounds over all scenes; each scene keeps its fastest round, which filters out clock and power-state noise.")
    var repeats = 3

    @Option var width = 1_024
    @Option var height = 1_024

    @Option(help: "Allowed CPU slowdown as a fraction of the baseline median.")
    var margin = 0.15

    @Option(help: "Allowed GPU slowdown as a fraction of the baseline median. GPU times vary more between runs (clock states).")
    var gpuMargin = 0.5

    @Option(help: "Slowdowns smaller than this many milliseconds are noise, whatever the fraction.")
    var noiseFloor = 0.3

    @Option(help: "Allowed load-time slowdown as a fraction of the baseline. Load times vary with the file cache.")
    var loadMargin = 0.25

    @Option(help: "Load-time slowdowns smaller than this many milliseconds are noise.")
    var loadNoiseFloor = 5.0

    @Argument(help: "Only these scenes (default: all).")
    var only: [String] = []

    func run() throws {
        try MainActor.assumeIsolated {
            try bench()
        }
    }

    @MainActor
    func bench() throws {
        #if DEBUG
        guard !record else {
            throw ValidationError("Refusing to record a baseline from a Debug build; build with -c release.")
        }
        print("warning: Debug build; timings are several times slower than Release and not comparable with a baseline.")
        #endif
        let unknown = Set(only).subtracting(Self.scenes.map(\.name))
        guard unknown.isEmpty else {
            throw ValidationError("Unknown scenes: \(unknown.sorted().joined(separator: ", ")). Known: \(Self.scenes.map(\.name).joined(separator: ", "))")
        }
        let selected = Self.scenes.filter { only.isEmpty || only.contains($0.name) }
        let machine = Self.sysctl("hw.model") ?? "unknown"
        let baselineURL = URL(fileURLWithPath: baselines).appending(path: "\(machine).json")
        let existing = try? JSONDecoder.iso.decode(Baseline.self, from: Data(contentsOf: baselineURL))
        if !record, existing == nil {
            print("No baseline for \(machine) at \(baselineURL.path); run with --record to make one.")
        }

        // One renderer per size; scenes may override the default size.
        var renderers: [String: OffscreenRenderer] = [:]
        func renderer(for scene: Scene) throws -> OffscreenRenderer {
            let size = scene.size ?? (width, height)
            let key = "\(size.width)x\(size.height)"
            if let existing = renderers[key] {
                return existing
            }
            let made = try OffscreenRenderer(size: CGSize(width: size.width, height: size.height), clearDepth: 0)
            renderers[key] = made
            return made
        }
        var results: [String: FrameTimings] = [:]
        var regressions: [String] = []
        var loaded: [(scene: Scene, asset: GLTFAsset)] = []
        // Fastest load of each scene, in milliseconds (#558). The first load includes a cold file cache, so each scene
        // is loaded once per round and keeps its fastest.
        var loadTimes: [String: Double] = [:]
        for scene in selected {
            let url = URL(fileURLWithPath: models).appending(path: scene.path)
            guard FileManager.default.fileExists(atPath: url.path) else {
                print("\(scene.name): missing \(url.path); run `just download-sample-assets`.")
                continue
            }
            var asset: GLTFAsset?
            for _ in 0 ..< max(repeats, 1) {
                let start = ContinuousClock.now
                asset = try GLTFAsset(url: url, options: .commandLine)
                let elapsed = ContinuousClock.now - start
                let milliseconds = Double(elapsed.components.seconds) * 1_000 + Double(elapsed.components.attoseconds) / 1e15
                loadTimes[scene.name] = min(loadTimes[scene.name] ?? .infinity, milliseconds)
            }
            // swiftlint:disable:next force_unwrapping - loaded at least once above
            let loadedAsset = asset!
            if let animation = scene.animation, !loadedAsset.animations.indices.contains(animation) {
                throw ValidationError("\(scene.name) has no animation \(animation)")
            }
            if scene.switchesVariants, loadedAsset.variantNames.count < 2 {
                throw ValidationError("\(scene.name) has fewer than two material variants")
            }
            loaded.append((scene, loadedAsset))
        }
        // Run every scene once per round, not one scene many times. A cold start then affects only the first round.
        // Each scene keeps its fastest round.
        var rounds: [[FrameTimings]] = []
        for _ in 0 ..< max(repeats, 1) {
            rounds.append(try loaded.map { try measure($0.scene, asset: $0.asset, renderer: try renderer(for: $0.scene)) })
        }
        print("scene".padding(toLength: 26, withPad: " ", startingAt: 0) + "     cpu ms     gpu ms    load ms   vs baseline (median)")
        for (index, (scene, _)) in loaded.enumerated() {
            let runs = rounds.map { $0[index] }
            // CPU and GPU are judged separately, so each takes its own fastest run.
            // swiftlint:disable:next force_unwrapping - there is at least one run
            var timings = runs.min { $0.frame.median < $1.frame.median }!
            // swiftlint:disable:next force_unwrapping - there is at least one run
            timings.cpu = runs.map(\.cpu).min { $0.median < $1.median }!
            // swiftlint:disable:next force_unwrapping - there is at least one run
            timings.gpu = runs.map(\.gpu).min { $0.median < $1.median }!
            results[scene.name] = timings
            var comparison = ""
            let loadTime = loadTimes[scene.name] ?? 0
            if let old = existing?.scenes[scene.name] {
                let cpu = change(timings.cpu.median, from: old.cpu.median, margin: margin)
                let gpu = change(timings.gpu.median, from: old.gpu.median, margin: gpuMargin)
                comparison = "cpu \(cpu.text)  gpu \(gpu.text)"
                var isRegression = cpu.isRegression || gpu.isRegression
                if let oldLoad = existing?.loadTimes?[scene.name] {
                    let load = change(loadTime, from: oldLoad, margin: loadMargin, noiseFloor: loadNoiseFloor)
                    comparison += "  load \(load.text)"
                    isRegression = isRegression || load.isRegression
                }
                if !record, isRegression {
                    regressions.append(scene.name)
                    comparison += "  REGRESSION"
                }
            }
            print(scene.name.padding(toLength: 26, withPad: " ", startingAt: 0) + String(format: " %10.3f %10.3f %10.1f   ", timings.cpu.median, timings.gpu.median, loadTime) + comparison)
        }

        if record {
            // Keep baselines of scenes not run this time.
            var scenes = existing?.scenes ?? [:]
            scenes.merge(results) { $1 }
            var allLoadTimes = existing?.loadTimes ?? [:]
            allLoadTimes.merge(loadTimes) { $1 }
            let baseline = Baseline(machine: machine, chip: Self.sysctl("machdep.cpu.brand_string") ?? "unknown", recorded: Date(), frames: frames, width: width, height: height, scenes: scenes, loadTimes: allLoadTimes)
            try FileManager.default.createDirectory(at: baselineURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder.iso.encode(baseline).write(to: baselineURL)
            print("Wrote \(baselineURL.path)")
        } else if !regressions.isEmpty {
            print("Slower than baseline by more than \(Int(margin * 100))% CPU, \(Int(gpuMargin * 100))% GPU or \(Int(loadMargin * 100))% load, past the noise floors: \(regressions.joined(separator: ", "))")
            throw ExitCode(1)
        }
    }

    @MainActor
    func measure(_ scene: Scene, asset: GLTFAsset, renderer: OffscreenRenderer) throws -> FrameTimings {
        let size = scene.size ?? (width, height)
        let camera = PBRCamera.framing(asset.bounds, aspectRatio: Float(size.width) / Float(size.height))
        let lighting = PBRLighting(asset: asset)
        let viewportSize = CGSize(width: size.width, height: size.height)
        // Variants share the asset's resources; switching picks another asset each frame.
        let variants = scene.switchesVariants ? try asset.variantNames.indices.map { try asset.variant($0) } : [asset]
        return try measureFrames(frames: frames, warmUpFrames: 30, renderer: renderer) { frame in
            let asset = variants[frame % variants.count]
            return GLTFScene(
                asset: asset,
                viewMatrix: camera.viewMatrix,
                projectionMatrix: camera.projectionMatrix,
                modelMatrix: scene.orbit ? orbitMatrix(center: asset.bounds.center, frame: frame) : matrix_identity_float4x4,
                lighting: lighting,
                pose: scene.animation.map { asset.pose(animation: $0, time: Float(frame) / 60) },
                showsBackground: scene.showsBackground,
                viewportSize: viewportSize
            )
        }
    }

    func change(_ new: Double, from old: Double, margin: Double, noiseFloor: Double? = nil) -> (text: String, isRegression: Bool) {
        let fraction = old > 0 ? (new - old) / old : 0
        let text = String(format: "%+6.1f%%", fraction * 100)
        return (text, new - old > (noiseFloor ?? self.noiseFloor) && fraction > margin)
    }

    static func sysctl(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else {
            return nil
        }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else {
            return nil
        }
        return String(bytes: buffer.prefix { $0 != 0 }, encoding: .utf8)
    }
}

private extension JSONEncoder {
    static var iso: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var iso: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
