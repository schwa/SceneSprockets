import GeometryLite3D
import Metal
import MetalSprocketsSupport
import MetalSupport
import Observation
import SceneSprockets
import SceneSprocketsBlinnPhong
import SceneSprocketsGizmos
import simd
import SwiftMesh
import SwiftUI

public enum DemoSection: String, CaseIterable, Sendable {
    case basics = "Basics"
}

// A catalog entry. `make` builds a fresh scene each time the demo is opened.
public struct Demo: Identifiable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var systemImage: String
    public var section: DemoSection
    public var summary: String
    public var make: @MainActor @Sendable () -> DemoScene

    public init(id: String, title: String, systemImage: String, section: DemoSection, summary: String, make: @escaping @MainActor @Sendable () -> DemoScene) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.section = section
        self.summary = summary
        self.make = make
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

public struct DemoParameter: Identifiable, Sendable {
    public enum Kind: Sendable {
        case slider(ClosedRange<Float>)
        case toggle
        case choice([String])
    }

    public var id: String { name }
    public var name: String
    public var kind: Kind
    public var defaultValue: Float

    public static func slider(_ name: String, _ range: ClosedRange<Float>, default defaultValue: Float) -> Self {
        Self(name: name, kind: .slider(range), defaultValue: defaultValue)
    }

    public static func toggle(_ name: String, default defaultValue: Bool) -> Self {
        Self(name: name, kind: .toggle, defaultValue: defaultValue ? 1 : 0)
    }

    // The value is the index of the chosen option.
    public static func choice(_ name: String, _ options: [String], default defaultIndex: Int = 0) -> Self {
        Self(name: name, kind: .choice(options), defaultValue: Float(defaultIndex))
    }
}

public struct DemoAction: Identifiable {
    public var id: String { name }
    public var name: String
    public var systemImage: String
    // A key with no modifiers that runs the action, such as .rightArrow.
    public var shortcut: KeyEquivalent?
    public var perform: @MainActor () -> Void

    public init(_ name: String, systemImage: String, shortcut: KeyEquivalent? = nil, perform: @escaping @MainActor () -> Void) {
        self.name = name
        self.systemImage = systemImage
        self.shortcut = shortcut
        self.perform = perform
    }
}

// Base class for demos. Subclasses build the scene in init and animate it in update(time:deltaTime:).
@MainActor
@Observable
open class DemoScene {
    @ObservationIgnored public let sceneGraph: SceneGraph
    @ObservationIgnored public var renderers: [any SceneGraphMaterialRenderer]
    @ObservationIgnored public let initialCameraMatrix: simd_float4x4
    public let parameters: [DemoParameter]
    public var values: [String: Float]
    @ObservationIgnored public var actions: [DemoAction] = []
    // Set to draw shadows from directional lights.
    // Observed: the view needs different texture settings with and without shadows.
    public var shadows: SceneGraphShadows?
    // Set to draw every mesh in a debug view instead of its material.
    public var debugMode: SceneGraphDebugMode?
    // Bumped when the hierarchy or visibility changes, so outline views refresh.
    public private(set) var outlineRevision = 0
    // Shared by the outline and click-to-select in the view.
    public var selectedNodeID: SceneGraph.Node.ID?
    // Draws an outline around the selected node.
    public var showsSelectionOutline = false
    // Overrides the view's gizmo mode picker while set, so a demo can show each mode.
    public var gizmoMode: TransformGizmo.Mode?
    // Only nodes in these categories can be picked.
    public var pickCategoryBitMask: UInt = .max
    // True when the demo moves its own camera node: the view then turns off user camera control.
    @ObservationIgnored public var usesSceneCamera = false

    public init(sceneGraph: SceneGraph, renderers: [any SceneGraphMaterialRenderer] = [BlinnPhongMaterialRenderer()], cameraMatrix: simd_float4x4, parameters: [DemoParameter] = []) {
        self.sceneGraph = sceneGraph
        self.renderers = renderers
        self.initialCameraMatrix = cameraMatrix
        self.parameters = parameters
        self.values = Dictionary(uniqueKeysWithValues: parameters.map { ($0.name, $0.defaultValue) })
    }

    public subscript(value name: String) -> Float {
        get { values[name] ?? 0 }
        set { values[name] = newValue }
    }

    public subscript(flag name: String) -> Bool {
        get { self[value: name] != 0 }
        set { self[value: name] = newValue ? 1 : 0 }
    }

    // Called every frame before rendering. `time` stops while paused; `deltaTime` is 0 while paused.
    open func update(time _: Float, deltaTime _: Float) {
    }

    public func toggleVisibility(of node: SceneGraph.Node) {
        node.isVisible.toggle()
        outlineRevision += 1
    }

    public func hierarchyDidChange() {
        outlineRevision += 1
    }

    // Selects the hit node (nil clears the selection), then calls `didPick`.
    public var selectedNode: SceneGraph.Node? {
        guard let selectedNodeID else {
            return nil
        }
        return sceneGraph.nodesWithWorldTransforms(includeHidden: true).first { $0.node.id == selectedNodeID }?.node
    }

    public func pick(_ hit: SceneGraph.Hit?) {
        selectedNodeID = hit?.node.id
        didPick(hit)
    }

    // Called after `pick`. Override to react to the hit (for example to place a marker).
    open func didPick(_: SceneGraph.Hit?) {
    }
}

// MARK: - Helpers for building demo scenes

public extension simd_float4x4 {
    static func translation(_ x: Float, _ y: Float, _ z: Float) -> simd_float4x4 {
        simd_float4x4(columns: ([1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0], [x, y, z, 1]))
    }

    static func scale(_ x: Float, _ y: Float, _ z: Float) -> simd_float4x4 {
        simd_float4x4(diagonal: [x, y, z, 1])
    }

    static func rotation(angle: Float, axis: SIMD3<Float>) -> simd_float4x4 {
        simd_float4x4(simd_quatf(angle: angle, axis: axis))
    }

    // A camera at `eye` looking at `target`, for use as a camera node's world transform.
    static func camera(eye: SIMD3<Float>, target: SIMD3<Float>, up: SIMD3<Float> = [0, 1, 0]) -> simd_float4x4 {
        let forward = simd_normalize(eye - target)
        let right = simd_normalize(simd_cross(up, forward))
        let trueUp = simd_cross(forward, right)
        return simd_float4x4(columns: (SIMD4(right, 0), SIMD4(trueUp, 0), SIMD4(forward, 0), SIMD4(eye, 1)))
    }
}

extension BlinnPhongSceneMaterial {
    static func plastic(_ color: SIMD3<Float>, shininess: Float = 32) -> BlinnPhongSceneMaterial {
        BlinnPhongSceneMaterial(ambient: .color(color * 0.1), diffuse: .color(color), specular: .color(0.5), shininess: shininess)
    }
}

extension Camera {
    // The demos' camera: 45° with a 100 m far plane.
    static let demo = Camera.perspective(fieldOfView: .degrees(45), zClip: 0.01 ... 100)
}

extension MetalMesh {
    // Reads a float3 vertex attribute back from shared-storage vertex buffers.
    func float3Attribute(_ semantic: VertexDescriptor.Attribute.Semantic) -> [SIMD3<Float>] {
        guard let attribute = vertexDescriptor.attributes.first(where: { $0.semantic == semantic }),
              attribute.format == .float3,
              let buffer = vertexBuffers[attribute.bufferIndex]
        else {
            return []
        }
        let stride = vertexDescriptor.layouts[attribute.bufferIndex]?.stride ?? 12
        let base = buffer.contents().advanced(by: attribute.offset)
        return (0..<vertexCount).map { index in
            let pointer = base.advanced(by: index * stride)
            return SIMD3(pointer.loadUnaligned(as: Float.self), pointer.loadUnaligned(fromByteOffset: 4, as: Float.self), pointer.loadUnaligned(fromByteOffset: 8, as: Float.self))
        }
    }
}

@MainActor let demoDevice = _MTLCreateSystemDefaultDevice()
