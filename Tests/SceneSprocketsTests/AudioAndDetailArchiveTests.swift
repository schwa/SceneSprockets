import AVFAudio
import Foundation
import Metal
@testable import SceneSprockets
import SceneSprocketsAudio
import SceneSprocketsBlinnPhong
import SceneSprocketsPBR
import SwiftMesh
import Testing

// #182: levels of detail and audio players survive a save and load.
@MainActor
struct AudioAndDetailArchiveTests {
    let device = MTLCreateSystemDefaultDevice()!

    func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(SceneArchive.pathExtension)
    }

    func material() -> BlinnPhongSceneMaterial {
        BlinnPhongSceneMaterial(ambient: .color(0.1), diffuse: .color([0.8, 0.5, 0.2]), specular: .color(0.3), shininess: 16)
    }

    @Test
    func levelsOfDetailRoundTrip() throws {
        let root = SceneGraph.Node(label: "Root")
        let node = root.addChild(SceneGraph.Node(label: "Rock", shape: .sphere(radius: 1), material: material()))
        let coarse = MetalMesh(mesh: .box(), device: device)
        node.levelsOfDetail = [SceneGraph.LevelOfDetail(mesh: coarse, distance: 10), SceneGraph.LevelOfDetail(mesh: nil, distance: 50)]
        let archive = SceneArchive(materialTypes: [BlinnPhongSceneMaterial.self], meshCodec: GLTFMeshCodec())
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let warnings = try archive.write(SceneGraph(root: root), to: url)
        #expect(!warnings.contains { $0.contains("levels of detail") })

        let (read, _) = try archive.read(from: url)
        let levels = try #require(read.root.children.first).levelsOfDetail
        try #require(levels.count == 2)
        #expect(levels[0].distance == 10)
        #expect(levels[0].mesh?.vertexCount == coarse.vertexCount)
        #expect(levels[1].distance == 50)
        #expect(levels[1].mesh == nil)
    }

    @Test
    func audioPlayersRoundTrip() throws {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 441))
        buffer.frameLength = 441
        for index in 0..<441 {
            buffer.floatChannelData?[0][index] = sin(Float(index) * 0.1) * 0.5
        }
        let root = SceneGraph.Node(label: "Root")
        let speaker = root.addChild(SceneGraph.Node(label: "Speaker"))
        speaker.audioPlayers = [AudioPlayer(buffer: buffer, loops: false, volume: 0.25)]
        let archive = SceneArchive()
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let warnings = try archive.write(SceneGraph(root: root), to: url)
        #expect(!warnings.contains { $0.contains("audio players") })

        let (read, _) = try archive.read(from: url)
        let player = try #require(read.root.children.first?.audioPlayers.first)
        #expect(player.loops == false)
        #expect(player.volume == 0.25)
        #expect(player.buffer.frameLength == 441)
        #expect(player.buffer.format.channelCount == 1)
        let sample = try #require(player.buffer.floatChannelData?[0][100])
        #expect(abs(sample - sin(10) * 0.5) < 1e-4)
    }
}
