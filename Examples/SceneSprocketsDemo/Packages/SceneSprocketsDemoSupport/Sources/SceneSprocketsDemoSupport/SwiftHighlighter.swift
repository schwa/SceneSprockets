import SwiftUI

// Just enough Swift highlighting for short slides: keywords, types, numbers, strings and comments.
enum SwiftHighlighter {
    private static let keywords: Set<String> = [
        "let", "var", "func", "for", "in", "return", "if", "else", "guard", "class", "struct", "enum", "true", "false", "nil", "self", "try", "await", "import"
    ]
    private static let plain = Color(white: 0.92)
    private static let keyword = Color(red: 0.99, green: 0.37, blue: 0.64)
    private static let type = Color(red: 0.36, green: 0.85, blue: 1)
    private static let member = Color(red: 0.4, green: 0.72, blue: 0.95)
    private static let number = Color(red: 0.82, green: 0.75, blue: 0.5)
    private static let string = Color(red: 0.99, green: 0.42, blue: 0.36)
    private static let comment = Color(white: 0.5)

    static func highlight(_ code: String) -> AttributedString {
        var result = AttributedString()
        func append(_ text: some StringProtocol, _ color: Color) {
            var run = AttributedString(String(text))
            run.foregroundColor = color
            result += run
        }
        let characters = Array(code)
        var index = 0
        var previous: Character = " "
        while index < characters.count {
            let character = characters[index]
            if character == "/", index + 1 < characters.count, characters[index + 1] == "/" {
                var end = index
                while end < characters.count, characters[end] != "\n" {
                    end += 1
                }
                append(String(characters[index..<end]), comment)
                index = end
            } else if character == "\"" {
                var end = index + 1
                while end < characters.count, characters[end] != "\"" {
                    end += 1
                }
                end = min(end + 1, characters.count)
                append(String(characters[index..<end]), string)
                index = end
            } else if character.isNumber {
                var end = index
                while end < characters.count, characters[end].isNumber || characters[end] == "." {
                    end += 1
                }
                append(String(characters[index..<end]), number)
                index = end
            } else if character.isLetter || character == "_" {
                var end = index
                while end < characters.count, characters[end].isLetter || characters[end].isNumber || characters[end] == "_" {
                    end += 1
                }
                let word = String(characters[index..<end])
                let color = if keywords.contains(word) {
                    keyword
                } else if word.first?.isUppercase == true {
                    type
                } else if previous == "." {
                    member
                } else {
                    plain
                }
                append(word, color)
                index = end
            } else {
                append(String(character), plain)
                index += 1
            }
            previous = characters[index - 1]
        }
        return result
    }
}
