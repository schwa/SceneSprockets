import GeometryLite3D
import SceneSprockets
import SceneSprocketsBlinnPhong
import simd
import SwiftUI

public struct TreeAppreciatorView: View {
    @State private var model = GameModel()
    @State private var leftShadows = SceneGraphShadows(intensity: 0.55, softness: 2)
    @State private var rightShadows = SceneGraphShadows(intensity: 0.55, softness: 2)

    public init() {}

    public var body: some View {
        HStack(spacing: 1) {
            treeView(side: .left)
            treeView(side: .right)
        }
        .background(.white.opacity(0.7))
        .ignoresSafeArea()
        .overlay(alignment: .top) { hud }
        .overlay(alignment: .bottom) { captionView }
        .overlay(alignment: .bottomTrailing) { buttons }
        .overlay { intro }
        .overlay(alignment: .bottom) { endCard }
        .animation(.easeInOut(duration: 0.6), value: model.showsIntro)
        .animation(.easeInOut(duration: 0.6), value: model.isComplete)
        .animation(.easeInOut(duration: 0.8), value: model.caption)
        .fontDesign(.serif)
    }

    @ViewBuilder
    private func treeView(side: Side) -> some View {
        if let world = side == .left ? model.left : model.right {
            SceneView(world.sceneGraph, renderers: [BlinnPhongMaterialRenderer(ambientLightColor: model.season.ambient)])
                .sceneCameraControl()
                .sceneDelegate(model.swayDriver)
                .sceneShadows(side == .left ? leftShadows : rightShadows)
                .sceneCamera(matrix: $model.cameraMatrix, target: model.cameraTarget)
                .sceneDefaultCamera(.perspective(zClip: 0.1 ... 1_000))
                .onSceneTap(id: model.levelID) { point, viewport, _ in
                    model.tap(side: side, point: point, viewport: viewport)
                }
            .id(model.levelID)
            .overlay(alignment: .top) {
                Text(side == .left ? model.leftName : model.rightName)
                    .italic()
                    .font(.title3)
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.5), radius: 6)
                    .padding(.top, 76)
            }
        }
    }

    private var hud: some View {
        HStack(spacing: 18) {
            Text("\(model.season.name) · \(model.season.treeKind) · \(GameModel.levelNames[model.level % GameModel.levelNames.count])")
                .pill()
            HStack(spacing: 8) {
                ForEach(model.differences) { difference in
                    Circle()
                        .fill(difference.found ? Color(red: 0.88, green: 0.66, blue: 0.23) : .clear)
                        .stroke(Color(red: 0.42, green: 0.35, blue: 0.23), lineWidth: difference.found ? 0 : 1.5)
                        .frame(width: 11, height: 11)
                        .scaleEffect(difference.found ? 1.25 : 1)
                        .shadow(color: difference.found ? .yellow : .clear, radius: 5)
                        .animation(.spring(duration: 0.5), value: difference.found)
                }
            }
            .pill()
            Text("\(model.score) appreciation")
                .contentTransition(.numericText())
                .animation(.default, value: model.score)
                .pill()
        }
        .padding(.top, 14)
    }

    @ViewBuilder
    private var captionView: some View {
        if let caption = model.caption {
            Text(caption)
                .italic()
                .font(.system(size: 28, design: .serif))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.55), radius: 10)
                .padding(.bottom, 70)
                .transition(.opacity)
                .id(caption)
        }
    }

    private var buttons: some View {
        HStack(spacing: 8) {
            Button("Hint") { model.hint() }
            Button(model.isMuted ? "Sound: off" : "Sound: on") { model.isMuted.toggle() }
            Button("New pair") { model.skipPair() }
        }
        .buttonStyle(PillButtonStyle())
        .padding(16)
    }

    @ViewBuilder
    private var intro: some View {
        if model.showsIntro {
            VStack(spacing: 14) {
                Text("Tree Appreciator")
                    .font(.system(size: 54, design: .serif))
                Text("Two trees grew from the same seed.\nThey are almost the same, but not quite.\n\nFind the places where they differ. Tap the spot on either tree.")
                    .multilineTextAlignment(.center)
                    .font(.title3)
                Text("Drag to walk around. Scroll or pinch to step closer.")
                    .italic()
                    .font(.title3)
                Button("Begin appreciating") { model.begin() }
                    .buttonStyle(PillButtonStyle())
                    .padding(.top, 8)
            }
            .card()
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private var endCard: some View {
        if model.isComplete {
            VStack(spacing: 10) {
                Text("\(model.season.name) pair appreciated")
                    .font(.system(size: 32, design: .serif))
                Text("\(model.differences.count) differences · \(model.squints) squints · \(model.hints) hints")
                Text("+\(model.completionBonus) attentiveness")
                Text(model.verdict).italic()
                Text("Take a moment. Drag to admire them.")
                    .font(.callout)
                Button("Next pair") {
                    withAnimation { model.nextPair() }
                }
                .buttonStyle(PillButtonStyle())
                .padding(.top, 6)
            }
            .font(.title3)
            .card()
            .padding(.bottom, 110)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }
}

private struct PillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, design: .serif))
            .foregroundStyle(Color(red: 0.17, green: 0.16, blue: 0.15))
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
            .background(Color(red: 1, green: 0.98, blue: 0.94).opacity(0.85), in: .capsule)
            .shadow(color: .black.opacity(0.15), radius: 9, y: 4)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
    }
}

private extension View {
    func pill() -> some View {
        font(.system(size: 18, design: .serif))
            .foregroundStyle(Color(red: 0.17, green: 0.16, blue: 0.15))
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: .capsule)
            .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
    }

    func card() -> some View {
        foregroundStyle(Color(red: 0.17, green: 0.16, blue: 0.15))
            .padding(.horizontal, 44)
            .padding(.vertical, 34)
            .frame(maxWidth: 560)
            .background(.regularMaterial, in: .rect(cornerRadius: 18))
            .shadow(color: .black.opacity(0.25), radius: 30, y: 20)
    }
}
