import SwiftUI

// A Swift snippet with syntax colors, shown over the bottom of the scene view (#630). Text, so it can be selected and
// copied, stays sharp at any size and is not touched by the scene's fog, lighting or post-processing.
struct CodeSampleView: View {
    var code: String
    var fontSize: CGFloat = 13

    var body: some View {
        Text(SwiftHighlighter.highlight(code))
            .font(.system(size: fontSize, design: .monospaced))
            .multilineTextAlignment(.leading)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .padding(fontSize)
            .background(Color(white: 0.11).opacity(0.92), in: .rect(cornerRadius: fontSize * 0.75))
            .overlay(RoundedRectangle(cornerRadius: fontSize * 0.75).strokeBorder(Color(white: 0.25), lineWidth: 1))
            .environment(\.colorScheme, .dark)
    }
}

#Preview {
    CodeSampleView(code: "let scene = SceneGraph()\nfor node in scene.root.children {\n    print(node)\n}")
        .padding()
}
