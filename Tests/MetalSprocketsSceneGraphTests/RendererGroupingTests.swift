import Metal
import MetalSupport
import SwiftMesh
import Testing
@testable import MetalSprocketsSceneGraph

@Test
func meshesWithDifferentVertexDescriptorsGetSeparateGroups() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let interleaved = MetalMesh(mesh: .box(), device: device, bufferLayout: .interleaved)
    let separate = MetalMesh(mesh: .box(), device: device, bufferLayout: .separateBuffers)
    #expect(interleaved.vertexDescriptor != separate.vertexDescriptor)

    let meshes = [interleaved, separate, interleaved]
    let groups = groupedByVertexDescriptor(meshes) { $0.vertexDescriptor }

    #expect(groups.count == 2)
    #expect(groups[0].vertexDescriptor == interleaved.vertexDescriptor)
    #expect(groups[0].entries.count == 2)
    #expect(groups[1].vertexDescriptor == separate.vertexDescriptor)
    #expect(groups[1].entries.count == 1)
}
