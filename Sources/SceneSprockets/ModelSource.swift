import Foundation

extension SceneGraph {
    /// A model file (such as a glTF and the buffers and images it loads), kept in memory so a scene archive can copy
    /// it into the package even when the original is no longer readable, as in the App Sandbox (#157).
    public struct ModelSource: Sendable, Hashable {
        /// The file to load, a key of `files`.
        public var mainFile: String
        /// File contents by path relative to the main file's folder.
        public var files: [String: Data]

        /// Creates a model source.
        ///
        /// - Parameters:
        ///   - mainFile: The file to load. It must be a key of `files`.
        ///   - files: The file contents, by path relative to the main file's folder.
        public init(mainFile: String, files: [String: Data]) {
            self.mainFile = mainFile
            self.files = files
        }

        /// Reads `url` and the files it names, given relative to its folder.
        public init(url: URL, relatedFiles: [String]) throws {
            let folder = url.deletingLastPathComponent()
            var files = [url.lastPathComponent: try Data(contentsOf: url)]
            for path in relatedFiles {
                files[path] = try Data(contentsOf: folder.appendingPathComponent(path))
            }
            self.init(mainFile: url.lastPathComponent, files: files)
        }
    }
}
