import Foundation
import GeometryLite3D
@testable import SceneSprockets
import Testing

// #593: the per-field lists must agree.

@Test
func everyNodeFieldStorageHasAWorldField() {
    let storageCount = Mirror(reflecting: SceneGraph.Node()).children.count { child in
        String(describing: type(of: child.value)).hasPrefix("NodeFieldStorage<")
    }
    #expect(storageCount == SceneGraph.Node.worldFields.count)
    let componentTypes = SceneGraph.Node.worldFields.map { "\($0.componentType)" }
    #expect(Set(componentTypes).count == componentTypes.count)
}

@Test
func everyArchiveKeyBelongsToOneField() {
    let fieldKeys = SceneGraph.Node.worldFields.flatMap(\.archiveKeys)
    #expect(Set(fieldKeys).count == fieldKeys.count)
    // Not fields: the subtree and a loaded model's file.
    let otherKeys: Set<SceneGraph.Node.ArchiveKeys> = [.children, .model]
    #expect(Set(fieldKeys).union(otherKeys) == Set(SceneGraph.Node.ArchiveKeys.allCases))
}

// #594: each world field is either copied into MeshEntry for drawing, or listed as not needed there and why. A new
// field fails until it is placed, so it cannot be silently left out of drawing.
@Test
func everyWorldFieldIsPlacedForDrawing() throws {
    // Field name -> the MeshEntry property it is drawn from, or nil when drawing does not read it from MeshEntry.
    let placement: [String: String?] = [
        "transform": "worldTransform",
        "pivot": "worldTransform",
        "content": "mesh",
        "opacity": "opacity",
        "categoryBitMask": "categoryBitMask",
        "renderingOrder": "renderingOrder",
        "levelsOfDetail": "levelsOfDetail",
        "skin": "skin",
        "skinVertices": "skinVertices",
        "morphTargets": "morphTargets",
        "morphWeights": "morphWeights",
        // Traversal skips hidden and inactive nodes, so they make no entries.
        "isVisible": nil,
        "isActive": nil,
        // Light nodes: Presentation.Light carries it.
        "lightCategoryBitMask": nil,
        // Drawn from Presentation.particleFrames and text entries, not mesh entries.
        "particleSystems": nil,
        "text": nil,
        // Drawn from Presentation.reflectors (#531).
        "planarReflector": nil,
        // Read from Presentation.probeVolumes (#532).
        "probeVolume": nil,
        // Applied to `content` before entries are made.
        "subdivisionLevel": nil,
        "subdivisionBase": nil,
        // Not drawn.
        "label": nil,
        "physicsBody": nil,
        // Read by followPath constraints and editor gizmos.
        "path": nil,
        "audioPlayers": nil,
        "runningActions": nil,
        "actionSpeed": nil,
        "constraints": nil,
        "accelerationStates": nil
    ]
    let names = SceneGraph.Node.worldFields.map(\.name)
    #expect(Set(names) == Set(placement.keys), "place these fields: \(Set(names).symmetricDifference(placement.keys).sorted())")

    // MeshEntry's stored properties, in its copy-on-write storage objects.
    struct PlainMaterial: SceneMaterial {}
    let entry = try #require(SceneGraph(root: SceneGraph.Node(shape: .box(), material: PlainMaterial())).meshEntries().first)
    var labels: Set<String> = []
    func collect(_ value: Any, depth: Int) {
        for child in Mirror(reflecting: value).children {
            if let label = child.label {
                labels.insert(label)
            }
            if depth < 2, child.label == "storage" || child.label == "shared" {
                collect(child.value, depth: depth + 1)
            }
        }
    }
    collect(entry, depth: 0)
    for case let (name, property?) in placement {
        #expect(labels.contains(property), "\(name) is drawn from MeshEntry.\(property), which does not exist")
    }
}

// #594: archiving writes and reads every field that has archive keys. Each such field gets a sample value here, or is
// listed as covered by a round-trip test elsewhere; a new archived field fails until it is added.
@Test
@MainActor
func everyArchivedFieldRoundTrips() throws {
    let samples: [String: (SceneGraph.Node) -> Void] = [
        "transform": { $0.transform = Transform3D(translation: [1, 2, 3]) },
        "content": { $0.content = .light(Light(type: .point, intensity: 3)) },
        "label": { $0.label = "sample" },
        "isVisible": { $0.isVisible = false },
        "isActive": { $0.isActive = false },
        "opacity": { $0.opacity = 0.5 },
        "pivot": { $0.pivot = Transform3D(translation: [0.1, 0.2, 0.3]).matrix },
        "categoryBitMask": { $0.categoryBitMask = 4 },
        "lightCategoryBitMask": { $0.lightCategoryBitMask = 2 },
        "renderingOrder": { $0.renderingOrder = 3 },
        "physicsBody": { $0.physicsBody = .init(type: .static, shape: .sphere(radius: 1)) },
        "morphWeights": { $0.morphWeights = [0.25, 0.75] },
        "actionSpeed": { $0.actionSpeed = 2 },
        "subdivisionLevel": { $0.subdivisionLevel = 1 },
        "path": { $0.path = SceneGraph.Spline(points: [[0, 0, 0], [1, 2, 3]], isClosed: true) },
        "planarReflector": { $0.planarReflector = SceneGraph.PlanarReflector(resolutionScale: 0.25) },
        "probeVolume": { $0.probeVolume = SceneGraph.ProbeVolume(resolution: [1, 1, 1], coefficients: [.zero]) }
    ]
    // Need other nodes, files or meshes to save; their round trips are in SceneArchiveTests and
    // AudioAndDetailArchiveTests.
    let coveredElsewhere: Set<String> = ["levelsOfDetail", "particleSystems", "audioPlayers", "text", "skin", "skinVertices", "morphTargets", "constraints"]
    let archived = SceneGraph.Node.worldFields.filter { !$0.archiveKeys.isEmpty }
    #expect(Set(archived.map(\.name)) == Set(samples.keys).union(coveredElsewhere), "add a sample for: \(Set(archived.map(\.name)).subtracting(samples.keys).subtracting(coveredElsewhere).sorted())")

    let archive = Archive()
    func nodeJSON(_ graph: SceneGraph) throws -> [String: Any] {
        let scene = try JSONSerialization.jsonObject(with: try archive.capture(graph).scene) as? [String: Any]
        let root = try #require(scene?["root"] as? [String: Any])
        return try #require((root["children"] as? [[String: Any]])?.first)
    }
    for slot in archived {
        guard let sample = samples[slot.name] else {
            continue
        }
        let root = SceneGraph.Node()
        let node = root.addChild(SceneGraph.Node())
        sample(node)
        let first = try nodeJSON(SceneGraph(root: root))
        #expect(slot.archiveKeys.contains { first[$0.rawValue] != nil }, "\(slot.name) is not written")
        // Reading it back and writing again gives the same node: the field was read.
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(Archive.pathExtension)
        defer { try? FileManager.default.removeItem(at: url) }
        try archive.write(SceneGraph(root: root), to: url)
        let second = try nodeJSON(try archive.read(from: url).sceneGraph)
        func canonical(_ object: [String: Any]) throws -> Data {
            try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        }
        #expect(try canonical(first) == canonical(second), "\(slot.name) is not read back: \(first) vs \(second)")
    }
}

@Test
func cloneCopiesWorldFields() {
    let node = SceneGraph.Node(label: "a")
    node.opacity = 0.5
    node.renderingOrder = 3
    node.actionSpeed = 2
    node.categoryBitMask = 4
    node.morphWeights = [0.25]
    let copy = node.clone()
    #expect(copy.label == "a")
    #expect(copy.opacity == 0.5)
    #expect(copy.renderingOrder == 3)
    #expect(copy.actionSpeed == 2)
    #expect(copy.categoryBitMask == 4)
    #expect(copy.morphWeights == [0.25])
}
