import Foundation

// Counts undo registrations, to tell an empty assistant turn from one that changed something: canUndo is also true
// for an empty group.
final class CountingUndoManager: UndoManager {
    private(set) var registrationCount = 0

    override func __registerUndoWithTarget(_ target: Any, handler undoHandler: @escaping @MainActor (Any) -> Void) {
        registrationCount += 1
        super.__registerUndoWithTarget(target, handler: undoHandler)
    }
}

// Makes everything the assistant changes in one turn a single undo step (#203). While a turn runs, the model
// registers its undo actions with a private UndoManager in one group. When the turn ends, the document's undo
// manager gets one action that undoes or redoes that whole group.
// Edits the user makes in the editor during a turn land in the same step.
@MainActor
final class AssistantTurnUndo {
    static let actionName = "Assistant Changes"

    private weak var model: EditorModel?
    private var documentUndoManager: UndoManager?
    private var turnUndoManager: CountingUndoManager?

    init(model: EditorModel) {
        self.model = model
    }

    var isRecording: Bool {
        turnUndoManager != nil
    }

    func begin() {
        guard let model, turnUndoManager == nil, let documentUndoManager = model.undoManager else {
            return
        }
        let turnUndoManager = CountingUndoManager()
        turnUndoManager.groupsByEvent = false
        turnUndoManager.beginUndoGrouping()
        self.documentUndoManager = documentUndoManager
        self.turnUndoManager = turnUndoManager
        model.undoManager = turnUndoManager
    }

    func end() {
        guard let model, let turnUndoManager, let documentUndoManager else {
            return
        }
        turnUndoManager.endUndoGrouping()
        model.undoManager = documentUndoManager
        self.turnUndoManager = nil
        self.documentUndoManager = nil
        guard turnUndoManager.registrationCount > 0 else {
            return
        }
        Self.registerUndo(on: documentUndoManager, turn: turnUndoManager, model: model)
    }

    // The model's actions register their reverses with the turn manager while it replays, so redo has the whole
    // group again.
    private static func registerUndo(on documentUndoManager: UndoManager, turn: UndoManager, model: EditorModel) {
        documentUndoManager.registerUndo(withTarget: model) { model in
            replay(turn, model: model, documentUndoManager: documentUndoManager) { $0.undo() }
            registerRedo(on: documentUndoManager, turn: turn, model: model)
        }
        documentUndoManager.setActionName(actionName)
    }

    private static func registerRedo(on documentUndoManager: UndoManager, turn: UndoManager, model: EditorModel) {
        documentUndoManager.registerUndo(withTarget: model) { model in
            replay(turn, model: model, documentUndoManager: documentUndoManager) { $0.redo() }
            registerUndo(on: documentUndoManager, turn: turn, model: model)
        }
        documentUndoManager.setActionName(actionName)
    }

    private static func replay(_ turn: UndoManager, model: EditorModel, documentUndoManager: UndoManager, _ action: (UndoManager) -> Void) {
        model.undoManager = turn
        action(turn)
        model.undoManager = documentUndoManager
    }
}
