import Foundation
@testable import SceneSprocketsComposerSupport
import Testing

// #484: block observers stay registered until they are removed; the owner going away is not enough.
@Test func observersAreRemovedWithTheirOwner() {
    let name = Notification.Name("NotificationObserversTests")
    nonisolated(unsafe) var count = 0
    var observers: NotificationObservers? = NotificationObservers(names: [name], queue: nil) { _ in
        count += 1
    }
    NotificationCenter.default.post(name: name, object: nil)
    #expect(count == 1)
    #expect(observers != nil)
    observers = nil
    NotificationCenter.default.post(name: name, object: nil)
    #expect(count == 1)
}
