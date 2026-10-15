import Metal
import MetalSprocketsSceneGraph
import SwiftUI

// A Swift snippet drawn by SwiftUI into a texture, shown on a plane. The texture's alpha cuts out the rounded panel.
@MainActor
enum CodePanel {
    static let pointsPerUnit: Float = 150

    static func node(code: String, fontSize: CGFloat = 26, device: MTLDevice) -> SceneGraph.Node? {
        let renderer = ImageRenderer(content: CodePanelView(code: code, fontSize: fontSize))
        renderer.scale = 2
        guard let image = renderer.cgImage else {
            return nil
        }
        guard let texture = makeTexture(image, device: device) else {
            return nil
        }
        // Unlit: the color comes from emission; the black-tinted diffuse texture only supplies alpha.
        let material = BlinnPhongSceneMaterial(ambient: .color(0), diffuse: .texture(texture, tint: .zero), specular: .color(0), shininess: 1, usesDiffuseTextureAlpha: true, emission: .texture(texture))
        let width = Float(image.width) / Float(renderer.scale) / pointsPerUnit
        let height = Float(image.height) / Float(renderer.scale) / pointsPerUnit
        return SceneGraph.Node(label: "Code", shape: .plane(width: width, height: height), material: material, device: device)
    }

    // Redraws the image as 8-bit sRGB RGBA (ImageRenderer may hand back other formats) and uploads it with mipmaps.
    private static func makeTexture(_ image: CGImage, device: MTLDevice) -> MTLTexture? {
        let width = image.width, height = image.height
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = context.data
        else {
            return nil
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm_srgb, width: width, height: height, mipmapped: true)
        descriptor.usage = .shaderRead
        guard let texture = device.makeTexture(descriptor: descriptor),
              let queue = device.makeCommandQueue(),
              let commandBuffer = queue.makeCommandBuffer(),
              let blit = commandBuffer.makeBlitCommandEncoder()
        else {
            return nil
        }
        texture.label = "Code Panel"
        texture.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0, withBytes: data, bytesPerRow: width * 4)
        blit.generateMipmaps(for: texture)
        blit.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        return texture
    }
}

private struct CodePanelView: View {
    var code: String
    var fontSize: CGFloat

    var body: some View {
        Text(SwiftHighlighter.highlight(code))
            .font(.system(size: fontSize, design: .monospaced))
            .multilineTextAlignment(.leading)
            .padding(fontSize)
            .background(Color(white: 0.11), in: .rect(cornerRadius: fontSize * 0.75))
            .overlay(RoundedRectangle(cornerRadius: fontSize * 0.75).strokeBorder(Color(white: 0.25), lineWidth: 2))
            .environment(\.colorScheme, .dark)
    }
}

// Just enough Swift highlighting for short slides: keywords, types, numbers, strings and comments.
enum SwiftHighlighter {
    private static let keywords: Set<String> = [
        "let", "var", "func", "for", "in", "return", "if", "else", "guard", "class", "struct", "enum", "true", "false", "nil", "self", "try", "await", "import",
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
