import Foundation

// A .gltf picked for Insert Model File whose buffers and textures are separate files (#206, #213). The sandbox grants
// only the picked file, so an alert explains this and offers to choose the folder before anything is inserted.
struct FolderAccessRequest: Identifiable {
    var file: URL
    var externalFileCount: Int

    var id: URL { file }

    static let title = "Allow Access to the Model's Folder"

    var message: String {
        let files = externalFileCount == 1 ? "1 other file" : "\(externalFileCount) other files"
        return "\(file.lastPathComponent) loads \(files) (buffers, textures) from its folder. macOS lets the app read them only if you choose that folder."
    }

    static func cancelledMessage(file: URL) -> String {
        "\(file.lastPathComponent) was not inserted: its folder was not chosen."
    }

    static func wrongFolderMessage(file: URL, folder: URL) -> String {
        "\(file.lastPathComponent) is not inside \(folder.lastPathComponent). Choose the folder that contains it."
    }
}
