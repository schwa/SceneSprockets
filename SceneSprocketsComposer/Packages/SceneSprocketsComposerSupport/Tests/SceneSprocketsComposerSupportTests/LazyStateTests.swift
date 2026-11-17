import SceneSprockets
@testable import SceneSprocketsComposerSupport
import Testing

// #489: a view's model is built the first time the view needs it, not each time the view is initialized.
@MainActor
@Test func lazyStateBuildsItsValueOnce() {
    let holder = LazyState<Int>()
    var builds = 0
    func make() -> Int {
        builds += 1
        return 42
    }
    #expect(builds == 0)
    #expect(holder.value(make) == 42)
    #expect(holder.value(make) == 42)
    #expect(builds == 1)
}

// Initializing ComposerView, as a parent's body does, builds no editor model.
@MainActor
@Test func composerViewInitBuildsNoModel() {
    let document = ComposerDocument()
    let view = ComposerView(document: document)
    #expect(view.builtModel == nil)
}
