import AppKit
import DemoKit
import Foundation
import MetalSprocketsSceneGraphDemos
import SwiftUI

// scenegraph-demos                         open the demo picker
// scenegraph-demos --list                  list demo ids
// scenegraph-demos --render <id> [file]    render a demo offscreen to a PNG (default: <id>.png)
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
    guard frames >= 0 else {
        fail("--frames must be a number")
    }
    guard arguments.count >= 2 else {
        fail("usage: scenegraph-demos --render <id> [file.png] [--size WxH] [--frames N]")
    }
    let id = arguments[1]
    let url = URL(fileURLWithPath: arguments.count >= 3 ? arguments[2] : "\(id).png")
    do {
        let image = try MainActor.assumeIsolated { try DemoSnapshot.render(demoID: id, width: size[0], height: size[1], frames: frames) { scene in
            if let slide, let keynote = scene as? KeynoteDemo {
                keynote.show(slide: slide)
            }
        } }
        try DemoSnapshot.writePNG(image, to: url)
        print(url.path)
    } catch {
        fail("\(error)")
    }
case nil:
    SceneGraphDemosApp.main()
default:
    fail("usage: scenegraph-demos [--list | --render <id> [file.png] [--size WxH] [--frames N]]")
}
