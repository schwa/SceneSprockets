import Synchronization

extension SceneGraph {
    /// Revisions come from one global counter, so values never repeat across nodes or graphs.
    public struct Revision: Hashable, Sendable {
        /// Hierarchy, content or root changes.
        public var structure: Int
        /// Local transform changes.
        public var transform: Int

        static func next() -> Int {
            counter.add(1, ordering: .relaxed).newValue
        }

        private static let counter = Atomic<Int>(0)
    }
}
