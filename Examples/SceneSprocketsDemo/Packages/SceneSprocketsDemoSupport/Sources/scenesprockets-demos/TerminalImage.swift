import CoreGraphics
import Darwin
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Draws images in the terminal with the kitty graphics protocol, replacing the previous frame in place.
enum TerminalImage {
    enum Failure: Error {
        case encodingFailed
    }

    // The terminal's size in pixels, less one row for the shell prompt; 640x400 if the terminal doesn't report it.
    static func defaultSize() -> [Int] {
        var size = winsize()
        guard ioctl(STDOUT_FILENO, TIOCGWINSZ, &size) == 0, size.ws_xpixel > 0, size.ws_ypixel > 0, size.ws_row > 1 else {
            return [640, 400]
        }
        let rowHeight = Int(size.ws_ypixel) / Int(size.ws_row)
        return [Int(size.ws_xpixel), Int(size.ws_ypixel) - rowHeight]
    }

    static func begin() {
        // Clear the screen and hide the cursor; restore it on Ctrl-C.
        write("\u{1B}[2J\u{1B}[?25l")
        signal(SIGINT) { _ in
            TerminalImage.end()
            exit(0)
        }
    }

    static func end() {
        // Delete the image, show the cursor.
        write("\u{1B}_Ga=d,d=I,i=1,q=2\u{1B}\\\u{1B}[?25h\n")
    }

    static func draw(_ image: CGImage) throws {
        let payload = try pngData(image).base64EncodedString()
        // Synchronized output (mode 2026): the terminal shows the frame only once all of it has arrived.
        var output = "\u{1B}[?2026h\u{1B}[H"
        var chunks = payload.utf8.chunked(4_096).makeIterator()
        var next = chunks.next()
        var first = true
        while let chunk = next {
            next = chunks.next()
            let more = next == nil ? 0 : 1
            // Image 1, placement 1 is replaced in place each frame; C=1 keeps the cursor still, q=2 silences replies.
            let control = first ? "a=T,f=100,i=1,p=1,q=2,C=1,m=\(more)" : "m=\(more)"
            output += "\u{1B}_G\(control);\(String(decoding: chunk, as: UTF8.self))\u{1B}\\"
            first = false
        }
        output += "\u{1B}[?2026l"
        write(output)
    }

    private static func write(_ string: String) {
        FileHandle.standardOutput.write(Data(string.utf8))
    }

    private static func pngData(_ image: CGImage) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw Failure.encodingFailed
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw Failure.encodingFailed
        }
        return data as Data
    }
}

private extension Collection {
    func chunked(_ size: Int) -> [SubSequence] {
        stride(from: 0, to: count, by: size).map { offset in
            let start = index(startIndex, offsetBy: offset)
            let end = index(start, offsetBy: size, limitedBy: endIndex) ?? endIndex
            return self[start..<end]
        }
    }
}
