import Foundation

// Block observers of NotificationCenter.default that are removed when this object goes away. A block observer stays
// registered until it is removed, even after its owner is freed (#484).
final class NotificationObservers {
    private let tokens: [any NSObjectProtocol]

    init(names: [Notification.Name], queue: OperationQueue?, using block: @escaping @Sendable (Notification) -> Void) {
        tokens = names.map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: queue, using: block)
        }
    }

    deinit {
        for token in tokens {
            NotificationCenter.default.removeObserver(token)
        }
    }
}
