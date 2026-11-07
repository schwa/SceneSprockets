import AppKit
import SceneSprockets
@testable import SceneSprocketsComposerSupport
import SwiftUI
import Testing

// #241: the inspector must survive the selection's light or material going away under it, as when the assistant
// converts or deletes things between view updates.
@MainActor
struct InspectorCrashTests {
    func host(_ model: EditorModel) -> NSHostingView<NodeInspectorView> {
        let view = NSHostingView(rootView: NodeInspectorView(model: model))
        view.frame = CGRect(x: 0, y: 0, width: 320, height: 900)
        view.layoutSubtreeIfNeeded()
        return view
    }

    func update(_ view: NSView) {
        view.needsLayout = true
        view.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        view.layoutSubtreeIfNeeded()
    }

    @Test
    func lightRemovedUnderTheInspector() throws {
        let model = EditorModel(sceneGraph: ComposerDocument().sceneGraph)
        model.addLight(.spot)
        let light = try #require(model.selectedNode)
        let view = host(model)
        // Not a light any more, then gone.
        light.content = .empty
        model.notify(.content)
        update(view)
        model.delete(light)
        update(view)
    }

    @Test
    func materialKindChangedUnderTheInspector() throws {
        let model = EditorModel(sceneGraph: ComposerDocument().sceneGraph)
        model.addShape(.box(), label: "Box")
        let box = try #require(model.selectedNode)
        let view = host(model)
        try model.editMaterials(of: box, actionName: "Kind", [.kind(.pbr)])
        update(view)
        try model.editMaterials(of: box, actionName: "Kind", [.kind(.blinnPhong)])
        update(view)
        guard case let .mesh(mesh, _, _, _) = box.content else {
            return
        }
        box.content = .mesh(mesh, materials: [])
        model.notify(.content)
        update(view)
        model.selection = nil
        update(view)
    }
}
