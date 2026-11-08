import Metal
@testable import SceneSprockets
import SceneSprocketsAddOns
import SceneSprocketsBlinnPhong
import Testing

@Test
func sameSeedGrowsTheSameTree() {
    let parameters = ProceduralTree.Parameters.random(seed: 7)
    let first = ProceduralTree(parameters: parameters, seed: 7)
    let second = ProceduralTree(parameters: parameters, seed: 7)
    #expect(first.branches == second.branches)
    #expect(first.leaves == second.leaves)
    #expect(ProceduralTree(parameters: parameters, seed: 8).branches != first.branches)
}

@Test
func treeGrowsUpFromTheOrigin() throws {
    let tree = ProceduralTree()
    let trunk = try #require(tree.branches.first)
    #expect(trunk.start == .zero)
    #expect(trunk.end.y > 0)
    #expect(tree.branches.count > 30)
    #expect(!tree.leaves.isEmpty)
    #expect(tree.leaves.allSatisfy { tree.parameters.leafColors.indices.contains($0.colorIndex) })
}

@Test
func branchLimitStopsGrowth() {
    var parameters = ProceduralTree.Parameters()
    parameters.depth = 8
    parameters.maximumBranchCount = 50
    // The last branch to start finishes its 3 segments.
    #expect(ProceduralTree(parameters: parameters).branches.count <= 52)
}

@Test
func bareTreeHasNoLeaves() {
    var parameters = ProceduralTree.Parameters()
    parameters.leafColors = []
    #expect(ProceduralTree(parameters: parameters).leaves.isEmpty)
}

@Test
func nodeHasBarkAndLeafSubmeshes() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let tree = ProceduralTree()
    let node = tree.makeNode(device: device)
    guard case let .mesh(mesh, materials, _, _) = node.content else {
        Issue.record("The tree node has no mesh")
        return
    }
    let usedColors = Set(tree.leaves.map(\.colorIndex)).count
    #expect(mesh.submeshes.count == 1 + usedColors)
    #expect(materials.count == mesh.submeshes.count)
    #expect(materials.allSatisfy { $0 is BlinnPhongSceneMaterial })
    let bounds = try #require(mesh.positionBounds())
    #expect(bounds.min.y < 0.01)
    #expect(bounds.max.y > tree.parameters.trunkLength)
}
