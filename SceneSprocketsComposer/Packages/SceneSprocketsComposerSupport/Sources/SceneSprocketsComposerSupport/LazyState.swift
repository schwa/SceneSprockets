// Holds a value that is built the first time it is needed. Kept in @State, it stops a view from building an expensive
// model in init, which runs every time the parent's body makes the view again; SwiftUI keeps only the first (#489).
@MainActor
final class LazyState<Value> {
    private var stored: Value?

    var builtValue: Value? {
        stored
    }

    func value(_ make: () -> Value) -> Value {
        if let stored {
            return stored
        }
        let value = make()
        stored = value
        return value
    }
}
