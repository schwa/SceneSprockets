import GeometryLite3D
import MetalSprockets
import MetalSprocketsAddOns
import SceneSprockets
import simd

// How the editor preview draws the scene. Editor state only; not saved in the document.
struct RenderSettings: Equatable {
    var showsGrid = true
    var showsAxes = true
    // A light at the camera when the scene has none.
    var usesDefaultLighting = true
    var showsShadows = false
    var showsStatistics = false
    var outlinesSelection = true
    // Off keeps the drawable readable, for example to inspect it in a GPU capture.
    var isFramebufferOnly = true
    // Vertical, in degrees. Used when the scene has no camera node.
    var fieldOfView: Float = 60
    var nearClip: Float = 0.01
    var farClip: Float = 1_000

    static let gridColor: SIMD4<Float> = [1, 1, 1, 0.25]

    var options: SceneView.Options {
        var result: SceneView.Options = []
        if usesDefaultLighting {
            result.insert(.autoenablesDefaultLighting)
        }
        if showsStatistics {
            result.insert(.showsStatistics)
        }
        if !isFramebufferOnly {
            result.insert(.disablesFramebufferOnly)
        }
        return result
    }

    var camera: Camera {
        Camera(projection: PerspectiveProjection(verticalAngleOfView: .degrees(fieldOfView), depthMode: .standard(zClip: nearClip ... max(farClip, nearClip * 2))))
    }

    var shadows: SceneGraphShadows? {
        showsShadows ? SceneGraphShadows() : nil
    }

    // Grid and axes, drawn in the scene pass. SceneSprockets uses reversed depth: test with `.greater` and do not
    // write, so objects hide them.
    func decorations(context: SceneGraphRenderContext, drawableSize: SIMD2<Float>) throws -> AnyElement? {
        guard showsGrid || showsAxes, drawableSize.x > 0, drawableSize.y > 0 else {
            return nil
        }
        let viewProjection = context.projectionMatrix * context.viewMatrix
        return try MetalSprockets.Group {
            if showsGrid {
                GridShader(
                    projectionMatrix: context.projectionMatrix,
                    cameraMatrix: context.cameraMatrix,
                    gridColor: Self.gridColor,
                    // Transparent between the lines, so the scene shows through.
                    backgroundColor: [Self.gridColor.x, Self.gridColor.y, Self.gridColor.z, 0],
                    majorDivision: .init(interval: 10, color: [1, 1, 1, 0.4]),
                    depthCompareFunction: .greater,
                    writesDepth: false,
                    blendsWithBackground: true
                )
            }
            if showsAxes {
                try AxisLinesRenderPipeline(
                    mvpMatrix: viewProjection,
                    viewMatrix: context.viewMatrix,
                    projectionMatrix: context.projectionMatrix,
                    viewportSize: drawableSize
                )
                .depthCompare(function: .greater, writes: false)
            }
        }
        .eraseToAnyElement()
    }
}
