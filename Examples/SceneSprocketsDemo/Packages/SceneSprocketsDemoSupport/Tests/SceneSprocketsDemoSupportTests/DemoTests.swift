import CoreGraphics
import DemoKit
import GeometryLite3D
import Metal
import MetalSprockets
import SceneSprockets
import SceneSprocketsAddOns
import SceneSprocketsBlinnPhong
@testable import SceneSprocketsDemoSupport
import SceneSprocketsMaterialX
import simd
import Testing

@Test(arguments: DemoCatalog.demos)
@MainActor
func demoBuildsUpdatesAndRenders(demo: Demo) throws {
    let scene = demo.make()
    #expect(!scene.sceneGraph.cameraNodes().isEmpty)
    #expect(!scene.sceneGraph.meshEntries().isEmpty)
    for frame in 0..<3 {
        scene.update(time: Float(frame) / 60, deltaTime: 1 / 60)
    }
    #expect(!scene.sceneGraph.meshEntries().isEmpty)

    let size = CGSize(width: 64, height: 64)
    let element = SceneGraphElement(sceneGraph: scene.sceneGraph, cameraMatrix: scene.initialCameraMatrix, aspectRatio: 1, renderers: scene.renderers)
    let texture = try OffscreenRenderer(size: size).render(element).texture
    var pixels = [UInt8](repeating: 0, count: 64 * 64 * 4)
    texture.getBytes(&pixels, bytesPerRow: 64 * 4, from: MTLRegionMake2D(0, 0, 64, 64), mipmapLevel: 0)
    let litPixels = stride(from: 0, to: pixels.count, by: 4).filter { pixels[$0] > 8 || pixels[$0 + 1] > 8 || pixels[$0 + 2] > 8 }.count
    // Some demos have small objects at 64×64, so the bar is low.
    #expect(litPixels > 40, "\(demo.title) rendered almost nothing")
}

// Keynote slides share one value dictionary, so two slides with a control of the same name would share its value.
@Test
@MainActor
func keynoteSlideControlNamesAreUnique() {
    let names = KeynoteDemo.titles.flatMap(KeynoteDemo.slideParameters(for:)).map(\.name) + ["Slide", "Auto-advance", "Seconds per Slide"]
    #expect(Set(names).count == names.count, "\(Dictionary(grouping: names) { $0 }.filter { $0.value.count > 1 }.keys)")
}

// #489: initializing SceneDemoView, as a parent's body does, does not build the demo's scene.
@Test
@MainActor
func sceneDemoViewInitBuildsNoScene() throws {
    let demo = try #require(DemoCatalog.demos.first { $0.id == "keynote" })
    let view = SceneDemoView(demo: demo)
    #expect(view.builtScene == nil)
}

// #158: the dice demo's generated dice and gears are saved as glTF and read back as meshes.
@Test
@MainActor
func generatedDiceRoundTrip() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(Archive.pathExtension)
    defer { try? FileManager.default.removeItem(at: url) }
    let warnings = try DemoSnapshot.save(demoID: "dice", to: url, frames: 1)
    #expect(!warnings.contains { $0.contains("not a shape") })
    let saved = DemoCatalog.demos.first { $0.id == "dice" }!.make().sceneGraph.meshEntries().count
    let (loaded, readWarnings) = try DemoSnapshot.archive.read(from: url)
    #expect(readWarnings.isEmpty, "\(readWarnings)")
    #expect(loaded.meshEntries().count == saved)
}

// #69: the skinned tubes must sit on their skeletons, so bending curls them in place; with inverse bind matrices from
// the joints' world transforms they were offset and swung around far-away pivots.
@Test
@MainActor
func deformationSlideTubeFollowsItsSkeleton() throws {
    let graph = try keynoteShowing("Deformation").sceneGraph
    let nodes = graph.nodesWithWorldTransforms().map(\.node)
    let skeleton = try #require(nodes.first { $0.label == "Skeleton" })
    let tube = try #require(graph.meshEntries().first { $0.node.label == "Tube" })
    let positions = try #require(tube.deformed(revision: graph.revision)).mesh.positions()
    let skeletonX = skeleton.worldTransform.columns.3.x
    let baseX = positions.filter { $0.y < 0.05 }.map(\.x)
    // The base ring (weighted to joint 0, which never moves) stays around the skeleton.
    #expect(abs((baseX.min()! + baseX.max()!) / 2 - skeletonX) < 0.01, "tube base is not on its skeleton")
}

@MainActor
func keynoteShowing(_ title: String) throws -> KeynoteDemo {
    let keynote = KeynoteDemo()
    keynote.show(slide: try #require(KeynoteDemo.titles.firstIndex(of: title)))
    return keynote
}

// #618, #622: the demo's MaterialX file loads without warnings, and the MaterialX slide, not the glTF slide, shows a
// sphere for each material.
@Test
@MainActor
func materialXSlideShowsMaterialXMaterials() throws {
    let url = try #require(KeynoteDemo.materialXURL)
    let document = try MaterialXDocument(url: url)
    #expect(document.warnings.isEmpty, "\(document.warnings)")
    #expect(document.materials.count == 3)
    func spheres(_ title: String) throws -> Int {
        try keynoteShowing(title).sceneGraph.meshEntries().filter { $0.node.label?.hasPrefix("MaterialX ") == true }.count
    }
    #expect(try spheres("MaterialX") == 3)
    #expect(try spheres("glTF & Model I/O") == 0)
}

// #626: each Gizmos slide shape has its own gizmo mode; the selected one is draggable, the others are shown, and
// clicking a shape selects it.
@Test
@MainActor
func gizmosSlideShowsOneGizmoPerShape() throws {
    let keynote = try keynoteShowing("Gizmos")
    let box = try #require(keynote.selectedNode)
    #expect(box.label == "Box" && keynote.gizmoMode == .rotate)
    #expect(Set(keynote.displayGizmos.compactMap(\.node.label)) == ["Sphere", "Cone"])
    let cone = try #require(keynote.displayGizmos.first { $0.node.label == "Cone" }?.node)
    let hit = try #require(keynote.sceneGraph.hitTest(Ray3D(origin: cone.worldTransform.columns.3.xyz + [0, 0, 5], direction: [0, 0, -1])).first)
    keynote.pick(hit)
    #expect(keynote.selectedNode === cone && keynote.gizmoMode == .scale)
    #expect(Set(keynote.displayGizmos.compactMap(\.node.label)) == ["Sphere", "Box"])
    keynote.show(slide: 0)
    #expect(keynote.displayGizmos.isEmpty && keynote.gizmoMode == nil)
}

// #617: the Gizmos slide shows the editor gizmos, with the grid at the slide; the toggle and other slides hide them.
@Test
@MainActor
func gizmosSlideShowsEditorGizmos() throws {
    let index = try #require(KeynoteDemo.titles.firstIndex(of: "Gizmos"))
    let keynote = try keynoteShowing("Gizmos")
    #expect(keynote.editorGizmos.contains(.grid) && keynote.editorGizmos.contains(.lightsAndCameras))
    let slide = try #require(keynote.sceneGraph.root.children.first { $0.label == "Slide \(index + 1): Gizmos" })
    // At the slide, along X.
    #expect(keynote.editorGridTransform.columns.3.x == slide.worldTransform.columns.3.x)
    keynote[flag: "Editor Gizmos"] = false
    keynote.update(time: 0, deltaTime: 1.0 / 60)
    #expect(keynote.editorGizmos.isEmpty)
    keynote[flag: "Editor Gizmos"] = true
    keynote.update(time: 0, deltaTime: 1.0 / 60)
    #expect(!keynote.editorGizmos.isEmpty)
    keynote.show(slide: 0)
    #expect(keynote.editorGizmos.isEmpty)
}

// #616: the Lights slide has an ambient light node that the Ambient Light slider sets.
@Test
@MainActor
func lightsSlideHasAmbientLightNode() throws {
    let keynote = try keynoteShowing("Lights")
    func ambient() -> Light? {
        keynote.sceneGraph.lightNodes().map(\.light).first { $0.type == .ambient }
    }
    #expect(ambient()?.intensity == 0.15)
    keynote[value: "Ambient Light"] = 0.6
    keynote.update(time: 0, deltaTime: 1.0 / 60)
    #expect(ambient()?.intensity == 0.6)
}

// #615: the Materials slide has a parallax-mapped tile.
@Test
@MainActor
func materialsSlideHasParallaxTile() throws {
    let keynote = try keynoteShowing("Materials")
    let tile = try #require(keynote.sceneGraph.meshEntries().first { $0.node.label == "Parallax Tile" })
    let material = try #require(tile.material as? BlinnPhongSceneMaterial)
    #expect(material.heightMap != nil && material.parallaxDepth > 0)
}

// #614: Explicit Instancing swaps the crate nodes for instancedMesh nodes that draw the same crates.
@Test
@MainActor
func performanceSlideExplicitInstancingDrawsTheSameCrates() throws {
    let keynote = try keynoteShowing("Performance")
    keynote.update(time: 0.5, deltaTime: 1.0 / 60)
    func crateEntries() -> [SceneGraph.MeshEntry] {
        keynote.sceneGraph.meshEntries().filter { $0.node.label == "Crate" || $0.node.label == "Instanced Crates" }
    }
    let separate = crateEntries()
    #expect(!separate.isEmpty && separate.allSatisfy { $0.instanceIndex == nil })
    keynote[flag: "Explicit Instancing"] = true
    keynote.update(time: 0.5, deltaTime: 1.0 / 60)
    let instanced = crateEntries()
    #expect(instanced.count == separate.count)
    #expect(instanced.allSatisfy { $0.node.label == "Instanced Crates" && $0.instanceIndex != nil })
    // Same crates in the same places.
    let sortKey: (SIMD3<Float>) -> [Float] = { [($0.x * 100).rounded(), ($0.y * 100).rounded(), ($0.z * 100).rounded()] }
    let before = separate.map { sortKey($0.worldTransform.columns.3.xyz) }.sorted { $0.lexicographicallyPrecedes($1) }
    let after = instanced.map { sortKey($0.worldTransform.columns.3.xyz) }.sorted { $0.lexicographicallyPrecedes($1) }
    #expect(before == after)
}

// #613: the Fog slide shows volumetric fog, with shadows on for its shafts; the toggle turns it off and other slides
// have no fog.
@Test
@MainActor
func fogSlideShowsVolumetricFog() throws {
    let keynote = try keynoteShowing("Fog")
    keynote.update(time: 0, deltaTime: 1.0 / 60)
    #expect(keynote.sceneGraph.fog?.scattering != nil)
    #expect(keynote.shadows != nil)
    keynote[flag: "Volumetric Fog"] = false
    keynote.update(time: 0, deltaTime: 1.0 / 60)
    #expect(keynote.sceneGraph.fog != nil && keynote.sceneGraph.fog?.scattering == nil)
    keynote.show(slide: 0)
    keynote.update(time: 0, deltaTime: 1.0 / 60)
    #expect(keynote.sceneGraph.fog == nil)
}

// #612: the Paths slide's cars stay on the turning track's path and move along it.
@Test
@MainActor
func pathsSlideCarsFollowTheTrack() throws {
    let keynote = try keynoteShowing("Paths")
    let nodes = keynote.sceneGraph.nodesWithWorldTransforms().map(\.node)
    let track = try #require(nodes.first { $0.label == "Track" })
    let path = try #require(track.path)
    let car = try #require(nodes.first { $0.label == "Car" })
    func onPath() -> Bool {
        let local = (track.worldTransform.inverse * SIMD4(car.worldTransform.columns.3.xyz, 1)).xyz
        return (0 ..< 400).contains { simd_distance(path.position(at: Float($0) / 400), local) < 0.05 }
    }
    var positions: [SIMD3<Float>] = []
    for frame in 0 ..< 30 {
        keynote.update(time: Float(frame) / 60, deltaTime: 1.0 / 60)
        keynote.sceneGraph.advanceActions(by: 1.0 / 60)
        keynote.sceneGraph.applyConstraints(pointOfView: matrix_identity_float4x4)
        #expect(onPath(), "car left the track at frame \(frame)")
        positions.append(car.worldTransform.columns.3.xyz)
    }
    #expect(simd_distance(positions[0], positions[29]) > 0.2, "the car did not move")
}

// #628: the Many Lights slide looks the same with clustered lighting as with every light; overfull clusters used to
// drop lights and showed as rectangular tiles.
@Test
@MainActor
func manyLightsSlideClusteringMatchesEveryLight() throws {
    let keynote = try keynoteShowing("Many Lights")
    keynote.update(time: 1, deltaTime: 1.0 / 60)
    let cameraNode = keynote.usesSceneCamera ? keynote.sceneGraph.cameraNodes().first : nil
    let cameraMatrix = cameraNode?.worldTransform ?? keynote.initialCameraMatrix
    func render(_ clustering: LightClustering) throws -> [SIMD4<UInt8>] {
        let element = SceneGraphElement(sceneGraph: keynote.sceneGraph, cameraMatrix: cameraMatrix, aspectRatio: 1.6, renderers: keynote.renderers).lightClustering(clustering)
        let texture = try OffscreenRenderer(size: CGSize(width: 320, height: 200)).render(element).texture
        var pixels = [SIMD4<UInt8>](repeating: .zero, count: 320 * 200)
        texture.getBytes(&pixels, bytesPerRow: 320 * 4, from: MTLRegionMake2D(0, 0, 320, 200), mipmapLevel: 0)
        return pixels
    }
    let off = try render(.off)
    let on = try render(.on)
    let differences = zip(off, on).map { pair in
        let difference = SIMD4<Int>(truncatingIfNeeded: pair.0) &- SIMD4<Int>(truncatingIfNeeded: pair.1)
        return max(abs(difference.x), abs(difference.y), abs(difference.z))
    }
    // Lights are summed in a different order, so a rounding step is allowed.
    #expect((differences.max() ?? 0) <= 2, "clustered image differs by \(differences.max() ?? 0)")
}

// #611: the Many Lights slide shows enough lights to be clustered, and every one lights the whole slide, so its batches
// keep the clusters (batches lit by only some of the frame's lights do not use them).
@Test
@MainActor
func manyLightsSlideIsClustered() throws {
    let keynote = try keynoteShowing("Many Lights")
    keynote.update(time: 1, deltaTime: 1.0 / 60)
    let lights = keynote.sceneGraph.lightNodes()
    #expect(lights.count >= LightClustering.automaticMinimumLightCount)
    let masks = Set(lights.map(\.node.lightCategoryBitMask))
    #expect(masks.count == 1)
    let meshMasks = Set(keynote.sceneGraph.meshEntries().map(\.node.categoryBitMask))
    #expect(meshMasks.allSatisfy { mask in masks.allSatisfy { $0 & mask != 0 } })
}

// #624: bodies rebuilt when the More Physics slide restarts keep the slide's light bit, so they stay lit.
@Test
@MainActor
func morePhysicsRebuiltBodiesStayLit() throws {
    let index = try #require(KeynoteDemo.titles.firstIndex(of: "More Physics"))
    let keynote = try keynoteShowing("More Physics")
    let bit: UInt = 1 << UInt(index % UInt.bitWidth)
    // The slide restarts after 12 seconds.
    for frame in 0 ..< 13 * 30 {
        keynote.update(time: Float(frame) / 30, deltaTime: 1.0 / 30)
    }
    let bodies = keynote.sceneGraph.meshEntries().filter { ["Chain Link", "Chain Bob", "Crate", "Bouncing Ball"].contains($0.node.label) }
    #expect(!bodies.isEmpty)
    #expect(bodies.allSatisfy { $0.node.categoryBitMask == bit })
}

// #625: the character climbs the step instead of stopping at it.
@Test
@MainActor
func morePhysicsCharacterClimbsTheStep() throws {
    let keynote = try keynoteShowing("More Physics")
    let slide = try #require(keynote.sceneGraph.root.children.first { $0.label?.hasSuffix(": More Physics") == true })
    let walker = try #require(keynote.sceneGraph.nodesWithWorldTransforms().map(\.node).first { $0.label == "Character" })
    var farthest: Float = -.infinity
    // About 6 seconds: the character starts at x = 2.2 and the step is at x = 3.1...3.9.
    for frame in 0 ..< 6 * 60 {
        keynote.update(time: Float(frame) / 60, deltaTime: 1.0 / 60)
        farthest = max(farthest, walker.worldTransform.columns.3.x - slide.worldTransform.columns.3.x)
    }
    #expect(farthest > 4.2, "the character stopped at x = \(farthest)")
}

// #610: the More Physics slide's chain holds, crates float and the character walks.
@Test
@MainActor
func morePhysicsSlideSimulates() throws {
    let keynote = try keynoteShowing("More Physics")
    func nodes(_ label: String) -> [SceneGraph.Node] {
        keynote.sceneGraph.nodesWithWorldTransforms().map(\.node).filter { $0.label == label }
    }
    let slide = try #require(nodes("Slide \(KeynoteDemo.titles.firstIndex(of: "More Physics")! + 1): More Physics").first)
    let origin = slide.transform.translation
    let walker = try #require(nodes("Character").first)
    let walkerStart = walker.worldTransform.columns.3.x
    for frame in 0..<240 {
        keynote.update(time: Float(frame) / 60, deltaTime: 1.0 / 60)
    }
    let bob = try #require(nodes("Chain Bob").first)
    let bobOffset = bob.worldTransform.columns.3.xyz - (origin + [-4.5, 3.4, 0])
    #expect(simd_length(bobOffset) < 2.6, "the chain came apart")
    for crate in nodes("Crate") {
        let y = crate.worldTransform.columns.3.y
        #expect(y > 0.4 && y < 1.6, "crate at \(y) is not floating")
    }
    #expect(abs(walker.worldTransform.columns.3.x - walkerStart) > 0.5, "the character did not walk")
    #expect(walker.worldTransform.columns.3.y > -0.1, "the character fell through the floor")
}

// #329: picking a slide from the settings switches at once, with no transition.
@Test
@MainActor
func keynoteSlidePickerSwitchesInstantly() throws {
    let keynote = KeynoteDemo()
    let index = try #require(KeynoteDemo.titles.firstIndex(of: "Physics"))
    keynote[value: "Slide"] = Float(index)
    keynote.update(time: 0, deltaTime: 1.0 / 60)
    let slide = try #require(keynote.sceneGraph.root.children.first { $0.label == "Slide \(index + 1): Physics" })
    #expect(slide.opacity == 1)
    #expect(keynote[value: "Slide"] == Float(index))
}

// #441: slides publish their own controls, and only while they show.
@Test
@MainActor
func keynoteSlideControlsFollowTheSlide() throws {
    let keynote = try keynoteShowing("Physics")
    #expect(keynote.contextActions.map(\.name) == ["Roll Dice"])
    #expect(keynote[flag: "Auto-roll"])
    keynote.show(slide: try #require(KeynoteDemo.titles.firstIndex(of: "Metaballs")))
    #expect(keynote.contextActions.isEmpty)
    #expect(keynote.contextParameters.map(\.name) == ["Metaball Count", "Metaball Size", "Smoothing", "Metaball Lighting"])
    keynote.show(slide: try #require(KeynoteDemo.titles.firstIndex(of: "Voxels")))
    #expect(keynote.contextParameters.map(\.name) == ["Voxel Lighting"])
    keynote.show(slide: 0)
    #expect(keynote.contextParameters.isEmpty)
}

// #331: the presenter notes model follows the keynote's slide.
@Test
@MainActor
func keynotePresenterNotesFollowTheSlide() throws {
    let keynote = try keynoteShowing("Lights")
    let model = PresenterNotes.shared
    #expect(model.title == "Lights")
    #expect(model.slideCount == KeynoteDemo.titles.count)
    try #require(keynote.actions.first { $0.name == "Next" }).perform()
    let index = try #require(KeynoteDemo.titles.firstIndex(of: "Lights")) + 1
    #expect(model.slideIndex == index)
    #expect(model.title == KeynoteDemo.titles[index])
    #expect(model.nextTitle == KeynoteDemo.titles[index + 1])
    #expect(!model.notes.isEmpty)
}

// #332: every slide has presenter notes, and no notes belong to a slide that does not exist.
@Test
@MainActor
func keynoteEverySlideHasNotes() {
    #expect(Set(KeynoteDemo.notes.keys) == Set(KeynoteDemo.titles))
}

// #311: leaving the title slide breaks its titles into 3D letters that fall away; coming back restores them.
@Test
@MainActor
func keynoteTitleBreaksIntoTumblingLetters() throws {
    let keynote = KeynoteDemo()
    func letters() -> [SceneGraph.Node] {
        keynote.sceneGraph.nodesWithWorldTransforms(includeHidden: true).map(\.node).filter { $0.label?.hasPrefix("Letter ") == true }
    }
    let title = try #require(keynote.sceneGraph.nodesWithWorldTransforms(includeHidden: true).first { $0.node.label == "Title \"SceneSprockets\"" }?.node)
    try #require(keynote.actions.first { $0.name == "Next" }).perform()
    #expect(!title.isVisible)
    // "SceneSprockets" and "for MetalSprockets" without the space.
    #expect(letters().count == 31)
    for _ in 0 ..< 180 {
        keynote.update(time: 0, deltaTime: 1.0 / 60)
    }
    #expect(letters().isEmpty)
    keynote.show(slide: 0)
    #expect(title.isVisible)
}

// #317: the Thank You slide shows the title alone for half a second, then the finale.
@Test
@MainActor
func keynoteThankYouFinaleStartsAfterTheTitle() throws {
    let keynote = try keynoteShowing("Thank You")
    let finale = try #require(keynote.sceneGraph.nodesWithWorldTransforms(includeHidden: true).first { $0.node.label == "Finale" }?.node)
    #expect(!finale.isVisible)
    keynote.sceneGraph.advanceActions(by: 0.3)
    #expect(!finale.isVisible)
    keynote.sceneGraph.advanceActions(by: 0.3)
    #expect(finale.isVisible)
}

// #326: shadows are on from the start of a transition into the Shadows slide, and stay on until it has faded out.
@Test
@MainActor
func keynoteShadowsCoverTheShadowsSlideTransitions() throws {
    let shadowsIndex = try #require(KeynoteDemo.titles.firstIndex(of: "Shadows"))
    let keynote = try keynoteShowing(KeynoteDemo.titles[shadowsIndex - 1])
    let next = try #require(keynote.actions.first { $0.name == "Next" })
    next.perform()
    #expect(keynote.shadows != nil)
    next.perform()
    keynote.update(time: 0, deltaTime: 0.1)
    #expect(keynote.shadows != nil)
}

// #334: every slide uses the same camera height, so transitions only fly sideways.
@Test
@MainActor
func keynoteCameraHeightIsTheSameOnEverySlide() throws {
    let keynote = KeynoteDemo()
    var heights: Set<Float> = []
    for index in KeynoteDemo.titles.indices {
        keynote.show(slide: index)
        heights.insert(try #require(keynote.sceneGraph.cameraNodes().first).worldTransform.columns.3.y)
    }
    #expect(heights.count == 1)
}

// #333: the fog fades in with the transition to the Fog slide instead of switching on at the end.
@Test
@MainActor
func keynoteFogFadesInDuringTransition() throws {
    let keynote = try keynoteShowing("Shadows")
    try #require(keynote.actions.first { $0.name == "Next" }).perform()
    keynote.update(time: 0, deltaTime: 0.25)
    let fog = try #require(keynote.sceneGraph.fog)
    #expect(fog.endDistance > 34)
    for _ in 0 ..< 10 {
        keynote.update(time: 0, deltaTime: 0.25)
    }
    #expect(keynote.sceneGraph.fog?.endDistance == 34)
}

// #328: tapping an object outside the Gizmos slide selects nothing, so no gizmo appears.
@Test
@MainActor
func keynoteTapOutsideGizmosSlideSelectsNothing() throws {
    let keynote = try keynoteShowing("Materials")
    let index = try #require(KeynoteDemo.titles.firstIndex(of: "Materials"))
    let slide = try #require(keynote.sceneGraph.root.children.first { $0.label == "Slide \(index + 1): Materials" })
    let hits = keynote.sceneGraph.meshEntries().lazy.compactMap { entry -> SceneGraph.Hit? in
        var node: SceneGraph.Node? = entry.node
        while let current = node, current !== slide {
            node = current.parent
        }
        guard node != nil else {
            return nil
        }
        let target = entry.node.worldPosition
        return keynote.sceneGraph.hitTest(segmentFrom: target + [0, 0, 20], to: target - [0, 0, 20]).first
    }
    let hit = try #require(hits.first)
    keynote.pick(hit)
    #expect(keynote.selectedNodeID == nil)
}

// #70: the bump target moves vertices along the direction from the center, so vertices that share a position (one
// per face) move together and the surface does not tear.
@Test
@MainActor
func deformationSlideMorphKeepsSurfaceClosed() throws {
    let demo = try keynoteShowing("Deformation")
    let blob = try #require(demo.sceneGraph.meshEntries().first { $0.node.label == "Blob" })
    let positions = blob.mesh.positions()
    let deltas = try #require(blob.node.morphTargets.first).positionDeltas
    var deltaByPosition: [SIMD3<Int32>: SIMD3<Float>] = [:]
    for (position, delta) in zip(positions, deltas) {
        let key = SIMD3<Int32>((position * 10_000).rounded(.toNearestOrEven))
        if let existing = deltaByPosition[key] {
            #expect(simd_distance(existing, delta) < 1e-4)
        } else {
            deltaByPosition[key] = delta
        }
    }
}

// #112: the orthographic toggle swaps the camera's projection; it still renders, and a tap ray (built like SceneView's)
// through a shape's projected center hits that shape.
@Test
@MainActor
func sceneKitFeaturesOrthographicToggle() throws {
    let scene = SceneKitFeaturesDemo()
    scene[flag: "Orthographic"] = true
    scene.update(time: 0, deltaTime: 0)
    let cameraNode = try #require(scene.sceneGraph.cameraNodes().first?.node)
    guard case let .camera(camera) = cameraNode.content else {
        Issue.record("Expected a camera")
        return
    }
    #expect(camera.projection is OrthographicProjection)

    let viewSize = SIMD2<Float>(64, 64)
    let viewProjection = ViewProjection(viewMatrix: scene.initialCameraMatrix.inverse, projection: camera.projection, viewSize: viewSize)
    // The torus has a hole at its center; the sphere does not.
    let target = try #require(scene.sceneGraph.meshEntries().first { $0.node.label == "Sphere" }?.node)
    let point = try #require(viewProjection.project(target.worldPosition))
    let hit = scene.sceneGraph.hitTest(viewProjection.ray(through: [point.x, point.y]), options: .init(categoryBitMask: camera.categoryBitMask)).first
    #expect(hit?.node === target)

    scene[flag: "Orthographic"] = false
    scene.update(time: 0, deltaTime: 0)
    guard case let .camera(perspective) = cameraNode.content else {
        return
    }
    #expect(perspective.projection is PerspectiveProjection)
}

// #110: the opacity slider fades every shape through their group, and Fade takes the text out and back in.
@Test
@MainActor
func sceneKitFeaturesOpacityAndFade() throws {
    let scene = SceneKitFeaturesDemo()
    scene[value: "Shapes Opacity"] = 0.5
    scene.update(time: 0, deltaTime: 0)
    let shapes = scene.sceneGraph.meshEntries().filter { $0.node.parent?.label?.hasPrefix("Holder") == true }
    #expect(shapes.count == 6)
    #expect(shapes.allSatisfy { abs($0.opacity - 0.5) < 1e-6 && $0.isTransparent })

    let text = try #require(scene.sceneGraph.meshEntries().first { $0.node.label == "Glyphs" }?.node.parent)
    let fade = try #require(scene.actions.first { $0.name == "Fade" })
    fade.perform()
    scene.sceneGraph.advanceActions(by: 0.6)
    #expect(text.opacity < 1e-4)
    scene.sceneGraph.advanceActions(by: 1)
    #expect(text.opacity == 1)
}

// #111: the Blinn-Phong extras are in the scene, and the Cull Mode choice reaches the sphere's material.
@Test
@MainActor
func sceneKitFeaturesBlinnPhongExtras() throws {
    let scene = SceneKitFeaturesDemo()
    func material(_ label: String) throws -> BlinnPhongSceneMaterial {
        try #require(scene.sceneGraph.meshEntries().first { $0.node.label == label }?.material as? BlinnPhongSceneMaterial)
    }
    guard case .color(let emission) = try material("Emissive Sphere").emission else {
        Issue.record("Expected a color emission")
        return
    }
    #expect(emission != .zero)
    #expect(try material("Normal-Mapped Box").normalMap != nil)
    #expect(try material("Culled Sphere").renderState.cullMode == .none)
    scene[value: "Cull Mode"] = 2
    scene.update(time: 0, deltaTime: 0)
    #expect(try material("Culled Sphere").renderState.cullMode == .front)
}

// The bump map's normals tilt up (+Y, green above 0.5) on the upper half of each bump and down on the lower half.
@Test
@MainActor
func bumpNormalMapPointsUpOnTop() throws {
    let texture = try #require(SceneKitFeaturesDemo.bumpNormalMap(size: 128))
    func green(row: Int) -> UInt8 {
        var value = SIMD4<UInt8>.zero
        texture.getBytes(&value, bytesPerRow: 4, from: MTLRegionMake2D(16, row, 1, 1), mipmapLevel: 0)
        return value.y
    }
    // The first cell spans rows 0..<32 and is centered on row 16.
    #expect(green(row: 8) > 160)
    #expect(green(row: 24) < 96)
}

// The catalog and the app's picker come from one list (#116); ids must still be unique.
@Test
@MainActor
func catalogMatchesAppAndIDsAreUnique() {
    // The app adds custom DemoViews (Tree Appreciator) after the catalog's scene demos.
    let appIDs = SceneGraphDemos.all.map { $0.metadata.id.rawValue }
    #expect(Array(appIDs.prefix(DemoCatalog.demos.count)) == DemoCatalog.demos.map(\.id))
    #expect(Set(appIDs).count == appIDs.count)
}

// #529: every scene of the SDF demo builds a valid shape over time, and the demo shows each one.
@Test
@MainActor
func sdfDemoScenesBuildShapes() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    for scene in SDFDemo.scenes {
        // A spread of times, including ones where shapes are furthest apart.
        for time in stride(from: Float(0), through: 6.5, by: 0.25) {
            let shape = SDFDemo.shape(scene: scene, time: time, smoothing: 0.6, blobs: 6)
            #expect(shape.bounds != nil, "\(scene) at \(time)")
            let node = SceneGraph.Node()
            try node.setSignedDistanceShape(shape, surface: .blinnPhong(.plastic([1, 1, 1], shininess: 8)), device: device)
            guard case .mesh = node.content else {
                Issue.record("\(scene) made no mesh")
                continue
            }
        }
    }
    let demo = SDFDemo()
    for index in SDFDemo.scenes.indices {
        demo.values["Scene"] = Float(index)
        demo.update(time: 1, deltaTime: 1.0 / 60)
        let node = try #require(demo.sceneGraph.root.childNode(withLabel: "Signed Distance Shape"))
        guard case .mesh = node.content else {
            Issue.record("scene \(index) shows nothing")
            continue
        }
    }
}

@Test
@MainActor
func demoParametersHaveDefaults() {
    for demo in DemoCatalog.demos {
        let scene = demo.make()
        for parameter in scene.parameters {
            #expect(scene.values[parameter.name] == parameter.defaultValue)
        }
    }
}
