import AppKit
import DemoKit
import Foundation
import SceneSprocketDemos
import SwiftUI

// scenesprocket-demos                         open the demo picker
// scenesprocket-demos --list                  list demo ids
// scenesprocket-demos --render <id> [file]    render a demo offscreen to a PNG (default: <id>.png)
//                  [--size WxH] [--frames N] [--slide N] [--value Name=Number ...]
// scenesprocket-demos --video <id> [file]     record a demo offscreen to a movie (default: <id>.mov); the keynote
//                  [--size WxH] [--fps N]   auto-advances through every slide unless --seconds is given
//                  [--seconds N] [--slide N] [--value Name=Number ...]
// scenesprocket-demos --benchmark <id>        render every frame offscreen and print frame times
//                  [--size WxH] [--frames N] [--slide N]

struct SceneGraphDemosApp: App {
    init() {
        // A command-line executable is not a bundled app; make it a regular app with a Dock icon and focus.
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate()
    }

    var body: some Scene {
        DemoPickerScene(demos: SceneGraphDemos.all)
    }
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

var arguments = Array(CommandLine.arguments.dropFirst())

@MainActor
func option(_ name: String) -> String? {
    guard let index = arguments.firstIndex(of: name) else {
        return nil
    }
    guard index + 1 < arguments.count else {
        fail("\(name) needs a value")
    }
    let value = arguments[index + 1]
    arguments.removeSubrange(index...(index + 1))
    return value
}

// Demo parameters from repeated --value Name=Number; choices are indices.
@MainActor
func valueOptions() -> [String: Float] {
    var values: [String: Float] = [:]
    while let pair = option("--value") {
        let parts = pair.split(separator: "=", maxSplits: 1)
        guard parts.count == 2, let number = Float(parts[1]) else {
            fail("--value must look like Name=Number")
        }
        values[String(parts[0])] = number
    }
    return values
}

switch arguments.first {
case "--list":
    for demo in DemoCatalog.demos {
        print("\(demo.id)\t\(demo.title)")
    }
case "--render":
    let size = option("--size").map { $0.split(separator: "x").compactMap { Int($0) } } ?? [1280, 800]
    guard size.count == 2 else {
        fail("--size must look like 1280x800")
    }
    let frames = option("--frames").map { Int($0) ?? -1 } ?? 60
    let slide = option("--slide").flatMap { Int($0) }
    let values = valueOptions()
    guard frames >= 0 else {
        fail("--frames must be a number")
    }
    guard arguments.count >= 2 else {
        fail("usage: scenesprocket-demos --render <id> [file.png] [--size WxH] [--frames N]")
    }
    let id = arguments[1]
    let url = URL(fileURLWithPath: arguments.count >= 3 ? arguments[2] : "\(id).png")
    do {
        let image = try MainActor.assumeIsolated { try DemoSnapshot.render(demoID: id, width: size[0], height: size[1], frames: frames, values: values) { scene in
            if let slide, let keynote = scene as? KeynoteDemo {
                keynote.show(slide: slide)
            }
        } }
        try DemoSnapshot.writePNG(image, to: url)
        print(url.path)
    } catch {
        fail("\(error)")
    }
case "--video":
    let size = option("--size").map { $0.split(separator: "x").compactMap { Int($0) } } ?? [1920, 1080]
    let frameRate = option("--fps").flatMap { Double($0) } ?? 60
    let requestedSeconds = option("--seconds").flatMap { Double($0) }
    let slide = option("--slide").flatMap { Int($0) }
    var values = valueOptions()
    guard size.count == 2, arguments.count >= 2 else {
        fail("usage: scenesprocket-demos --video <id> [file.mov] [--size WxH] [--fps N] [--seconds N] [--slide N] [--value Name=Number ...]")
    }
    let id = arguments[1]
    let url = URL(fileURLWithPath: arguments.count >= 3 ? arguments[2] : "\(id).mov")
    // The keynote plays through: auto-advance, and long enough to show every slide once.
    var seconds = requestedSeconds ?? 10
    if id == "keynote" {
        if values["Auto-advance"] == nil {
            values["Auto-advance"] = 1
        }
        let secondsPerSlide = Double(values["Seconds per Slide"] ?? 6)
        values["Seconds per Slide"] = Float(secondsPerSlide)
        seconds = requestedSeconds ?? Double(KeynoteDemo.titles.count - (slide ?? 0)) * secondsPerSlide
    }
    Task { @MainActor in
        do {
            var lastReported = -1
            try await DemoSnapshot.video(demoID: id, to: url, width: size[0], height: size[1], seconds: seconds, frameRate: frameRate, values: values) { scene in
                if let slide, let keynote = scene as? KeynoteDemo {
                    keynote.show(slide: slide)
                }
            } progress: { frame, frameCount in
                let percent = (frame + 1) * 100 / frameCount
                if percent != lastReported, percent % 5 == 0 {
                    lastReported = percent
                    FileHandle.standardError.write(Data("\(percent)% (\(frame + 1)/\(frameCount) frames)\n".utf8))
                }
            }
            print(url.path)
            exit(0)
        } catch {
            fail("\(error)")
        }
    }
    RunLoop.main.run()
case "--benchmark":
    let size = option("--size").map { $0.split(separator: "x").compactMap { Int($0) } } ?? [1280, 800]
    let frames = option("--frames").flatMap { Int($0) } ?? 120
    let slide = option("--slide").flatMap { Int($0) }
    let values = valueOptions()
    guard size.count == 2, arguments.count >= 2 else {
        fail("usage: scenesprocket-demos --benchmark <id> [--size WxH] [--frames N] [--slide N]")
    }
    do {
        let times = try MainActor.assumeIsolated { try DemoSnapshot.benchmark(demoID: arguments[1], width: size[0], height: size[1], frames: frames) { scene in
            scene.values.merge(values) { $1 }
            if let slide, let keynote = scene as? KeynoteDemo {
                keynote.show(slide: slide)
            }
        } }
        let sorted = times.sorted()
        let mean = times.reduce(0, +) / Double(max(times.count, 1))
        func milliseconds(_ seconds: Double) -> String { String(format: "%.2f ms", seconds * 1000) }
        print("frames \(times.count)  mean \(milliseconds(mean)) (\(String(format: "%.1f", 1 / mean)) fps)  median \(milliseconds(sorted[sorted.count / 2]))  p95 \(milliseconds(sorted[sorted.count * 95 / 100]))  max \(milliseconds(sorted.last ?? 0))")
    } catch {
        fail("\(error)")
    }
case nil:
    SceneGraphDemosApp.main()
default:
    fail("usage: scenesprocket-demos [--list | --render <id> [file.png] [--size WxH] [--frames N]]")
}
