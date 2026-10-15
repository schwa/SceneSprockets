import GeometryLite3D
import Metal
import MetalSprockets
import MetalSprocketsAddOns
import MetalSprocketsAddOnsShaders
import MetalSupport
import simd

public struct SceneGraphRenderContext {
    public var viewMatrix: simd_float4x4
    public var projectionMatrix: simd_float4x4
    public var cameraMatrix: simd_float4x4
    public var lights: [(worldTransform: simd_float4x4, light: Light)]
    public var revision: SceneGraph.Revision
    public var environment: SceneGraph.Environment
    // The camera's categoryBitMask.
    public var categoryBitMask: UInt = .max
    // Parallel to `lights`: each light node's lightCategoryBitMask.
    public var lightCategoryBitMasks: [UInt] = []
}

// One renderer per material family. Add a family by conforming a new type; the scene graph core does not change.
public protocol SceneGraphMaterialRenderer {
    var materialType: any MetalSprocketsSceneGraph.Material.Type { get }
    func makeElement(entries: [SceneGraph.MeshEntry], context: SceneGraphRenderContext) throws -> AnyElement
}

// A renderer that can draw `SceneGraph.Environment.Background.environment`. The element asks each one in order and
// draws the first non-nil result before any meshes, even when the renderer has no entries.
public protocol SceneGraphBackgroundRenderer {
    func makeBackgroundElement(context: SceneGraphRenderContext) throws -> AnyElement?
}

// Renders every mesh entry in one pass by handing each material family to its renderer.
// Entries whose material type has no renderer are skipped.
// The view comes from `camera` (default: the first camera node) unless `cameraMatrix` overrides its world transform.
// With no camera node, `defaultCamera` is used at `cameraMatrix` (identity if nil).
// `defaultLight` is added at the camera when the scene has no lights, like SceneKit's autoenablesDefaultLighting.
public struct SceneGraphElement: Element {
    var sceneGraph: SceneGraph
    var camera: SceneGraph.Node?
    var cameraMatrix: simd_float4x4?
    var aspectRatio: Float
    var renderers: [any SceneGraphMaterialRenderer]
    var defaultCamera: Camera?
    var defaultLight: Light?
    var shadows: SceneGraphShadows?

    @MSEnvironment(\.renderPassDescriptor)
    private var renderPassDescriptor

    public init(sceneGraph: SceneGraph, camera: SceneGraph.Node? = nil, cameraMatrix: simd_float4x4? = nil, aspectRatio: Float, renderers: [any SceneGraphMaterialRenderer], defaultCamera: Camera? = nil, defaultLight: Light? = nil, shadows: SceneGraphShadows? = nil) {
        self.sceneGraph = sceneGraph
        self.camera = camera
        self.cameraMatrix = cameraMatrix
        self.aspectRatio = aspectRatio
        self.renderers = renderers
        self.defaultCamera = defaultCamera
        self.defaultLight = defaultLight
        self.shadows = shadows
    }

    public var body: some Element {
        get throws {
            guard let context = makeRenderContext(sceneGraph: sceneGraph, camera: camera, cameraMatrix: cameraMatrix, aspectRatio: aspectRatio, defaultCamera: defaultCamera, defaultLight: defaultLight) else {
                return EmptyElement().eraseToAnyElement()
            }
            let entries = sceneGraph.meshEntries().filter { $0.node.categoryBitMask & context.categoryBitMask != 0 }
            var elements: [AnyElement] = []
            if case .environment = context.environment.background {
                for case let renderer as any SceneGraphBackgroundRenderer in renderers {
                    if let background = try renderer.makeBackgroundElement(context: context) {
                        elements.append(background)
                        break
                    }
                }
            }
            // One batch per rendering order and set of affecting lights; each renderer draws its part of each batch.
            for batch in renderBatches(entries, context: context) {
                let partitions = partitionMeshEntries(batch.entries, renderers: renderers)
                elements += try zip(renderers, partitions).compactMap { renderer, entries in
                    entries.isEmpty ? nil : try renderer.makeElement(entries: entries, context: batch.context)
                }
            }
            let clearColor: MTLClearColor? = if case let .color(color) = context.environment.background {
                MTLClearColor(red: Double(color.x), green: Double(color.y), blue: Double(color.z), alpha: Double(color.w))
            } else {
                nil
            }
            // The shadow mask and fog passes read and write the view's textures, so they need the right usage.
            let postTargets: (color: MTLTexture, depth: MTLTexture)? = {
                guard let color = renderPassDescriptor?.colorAttachments[0].texture, let depth = renderPassDescriptor?.depthAttachment.texture,
                      color.usage.isSuperset(of: ShadowContext.requiredColorUsage), depth.usage.isSuperset(of: ShadowContext.requiredDepthUsage),
                      depth.storageMode != .memoryless
                else {
                    return nil
                }
                return (color, depth)
            }()
            let shadowFrame = try postTargets.flatMap { targets in
                try shadows?.prepare(entries: entries, context: context, bounds: sceneGraph.bounds, viewSize: (targets.color.width, targets.color.height))
            }
            let fog = postTargets == nil ? nil : sceneGraph.fog
            let scenePass = try makeScenePass(elements: elements, clearColor: clearColor, storesDepth: shadowFrame != nil || fog != nil)
            guard let postTargets, shadowFrame != nil || fog != nil else {
                return scenePass.eraseToAnyElement()
            }
            let inverseViewProjection = (context.projectionMatrix * context.viewMatrix).inverse
            // The shadow and post passes open their own encoders, so they are siblings of the scene pass.
            return try MetalSprockets.Group {
                if let shadowFrame {
                    ShadowCasterDepthPass(frame: shadowFrame)
                }
                scenePass
                if let shadows, let shadowFrame {
                    SceneShadowMaskPass(
                        frame: shadowFrame,
                        sceneDepthTexture: postTargets.depth,
                        outputTexture: postTargets.color,
                        viewProjection: context.projectionMatrix * context.viewMatrix,
                        intensity: shadows.intensity
                    )
                }
                if let fog {
                    FogPass(fog: fog, depthTexture: postTargets.depth, colorTexture: postTargets.color, inverseViewProjection: inverseViewProjection, cameraPosition: SIMD3(context.cameraMatrix.columns.3.x, context.cameraMatrix.columns.3.y, context.cameraMatrix.columns.3.z))
                }
            }
            .eraseToAnyElement()
        }
    }

    private func makeScenePass(elements: [AnyElement], clearColor: MTLClearColor?, storesDepth: Bool) throws -> some Element {
        // Reversed depth (near 1, far 0) for every renderer, because MetalSprocketsPBR requires it.
        try RenderPass {
            if storesDepth {
                // The view's depth texture is shared by every frame in flight, and Metal 4 does not track hazards:
                // without this, the previous frame's shadow mask pass can still be reading depth while this pass
                // clears it, and that frame's shadow disappears.
                QueueBarrier(after: .dispatch, before: [.vertex, .fragment])
            }
            ForEach(Array(elements.enumerated()), id: \.offset) { _, element in
                element
            }
        }
        .depthCompare(function: .greater, enabled: true)
        .renderPassDescriptorModifier { descriptor in
            descriptor.depthAttachment.clearDepth = 0
            // The shadow mask pass reads depth afterwards. Memoryless depth (the default) cannot be stored.
            if storesDepth {
                descriptor.depthAttachment.storeAction = .store
            }
            if let clearColor {
                descriptor.colorAttachments[0].clearColor = clearColor
                descriptor.colorAttachments[0].loadAction = .clear
            }
        }
    }
}

func makeRenderContext(sceneGraph: SceneGraph, camera: SceneGraph.Node?, cameraMatrix: simd_float4x4?, aspectRatio: Float, defaultCamera: Camera? = nil, defaultLight: Light? = nil) -> SceneGraphRenderContext? {
    let cameras = sceneGraph.cameraNodes()
    let entry = camera.map { camera in cameras.first { $0.node === camera } } ?? cameras.first
    let resolved: (camera: Camera, worldTransform: simd_float4x4)
    if let entry {
        resolved = (entry.camera, cameraMatrix ?? entry.worldTransform)
    } else if let defaultCamera {
        resolved = (defaultCamera, cameraMatrix ?? .identity)
    } else {
        return nil
    }
    let cameraMatrix = resolved.worldTransform
    let lightNodes = sceneGraph.lightNodes()
    var lights = lightNodes.map { (worldTransform: $0.worldTransform, light: $0.light) }
    var lightMasks = lightNodes.map(\.node.lightCategoryBitMask)
    if lights.isEmpty, let defaultLight {
        lights = [(cameraMatrix, defaultLight)]
        lightMasks = [.max]
    }
    return SceneGraphRenderContext(
        viewMatrix: cameraMatrix.inverse,
        projectionMatrix: reversedDepth * resolved.camera.projection.projectionMatrix(aspectRatio: aspectRatio),
        cameraMatrix: cameraMatrix,
        lights: lights,
        revision: sceneGraph.revision,
        environment: sceneGraph.environment,
        categoryBitMask: resolved.camera.categoryBitMask,
        lightCategoryBitMasks: lightMasks
    )
}

// Groups entries by rendering order (ascending), then opaque before transparent, then by the lights whose masks
// match, keeping first-seen order. Transparent entries are sorted farthest first. Each batch's context holds only
// its lights.
func renderBatches(_ entries: [SceneGraph.MeshEntry], context: SceneGraphRenderContext) -> [(entries: [SceneGraph.MeshEntry], context: SceneGraphRenderContext)] {
    struct Key: Hashable {
        var order: Int
        var isTransparent: Bool
        var lights: [Int]
    }
    var keys: [Key] = []
    var groups: [Key: [SceneGraph.MeshEntry]] = [:]
    for entry in entries {
        // Lights without a mask light everything.
        let lights = context.lights.indices.filter { index in
            let mask = index < context.lightCategoryBitMasks.count ? context.lightCategoryBitMasks[index] : .max
            return mask & entry.node.categoryBitMask != 0
        }
        let key = Key(order: entry.node.renderingOrder, isTransparent: entry.material.isTransparent, lights: lights)
        if groups[key] == nil {
            keys.append(key)
        }
        groups[key, default: []].append(entry)
    }
    let cameraPosition = SIMD3(context.cameraMatrix.columns.3.x, context.cameraMatrix.columns.3.y, context.cameraMatrix.columns.3.z)
    for key in keys where key.isTransparent {
        groups[key] = sortedBackToFront(groups[key] ?? [], cameraPosition: cameraPosition)
    }
    let allLights = Array(context.lights.indices)
    return keys.enumerated().sorted {
        ($0.element.order, $0.element.isTransparent ? 1 : 0, $0.offset) < ($1.element.order, $1.element.isTransparent ? 1 : 0, $1.offset)
    }
    .map { _, key in
        var batchContext = context
        if key.lights != allLights {
            batchContext.lights = key.lights.map { context.lights[$0] }
            batchContext.lightCategoryBitMasks = key.lights.map { $0 < context.lightCategoryBitMasks.count ? context.lightCategoryBitMasks[$0] : .max }
        }
        return (groups[key] ?? [], batchContext)
    }
}

// Maps clip-space z to w - z, so depth runs from 1 (near) to 0 (far).
let reversedDepth = simd_float4x4(columns: ([1, 0, 0, 0], [0, 1, 0, 0], [0, 0, -1, 0], [0, 0, 1, 1]))

// Returns one array per renderer, in renderer order.
func partitionMeshEntries(_ entries: [SceneGraph.MeshEntry], renderers: [any SceneGraphMaterialRenderer]) -> [[SceneGraph.MeshEntry]] {
    var indexByType: [ObjectIdentifier: Int] = [:]
    for (index, renderer) in renderers.enumerated() {
        indexByType[ObjectIdentifier(renderer.materialType)] = index
    }
    var partitions = Array(repeating: [SceneGraph.MeshEntry](), count: renderers.count)
    for entry in entries {
        if let index = indexByType[ObjectIdentifier(type(of: entry.material))] {
            partitions[index].append(entry)
        }
    }
    return partitions
}

extension Element {
    func vertexBuffers(_ buffers: [Int: MTLBuffer]) -> some Element {
        buffers.sorted { $0.key < $1.key }.reduce(AnyElement(self)) { element, entry in
            AnyElement(element.vertexBuffer(entry.value, index: entry.key))
        }
    }
}

// Groups entries by vertex descriptor, keeping first-seen order.
func groupedByVertexDescriptor<Entry>(_ entries: [Entry], vertexDescriptor: (Entry) -> VertexDescriptor) -> [(vertexDescriptor: VertexDescriptor, entries: [Entry])] {
    var groups: [(vertexDescriptor: VertexDescriptor, entries: [Entry])] = []
    for entry in entries {
        let descriptor = vertexDescriptor(entry)
        if let index = groups.firstIndex(where: { $0.vertexDescriptor == descriptor }) {
            groups[index].entries.append(entry)
        } else {
            groups.append((descriptor, [entry]))
        }
    }
    return groups
}
