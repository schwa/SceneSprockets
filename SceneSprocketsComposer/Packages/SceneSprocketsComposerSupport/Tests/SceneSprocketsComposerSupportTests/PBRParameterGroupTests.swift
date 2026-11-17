@testable import SceneSprocketsComposerSupport
import Testing

// #488: the material section reads each group's parameters from lists made once, not filtered on every pass.
@MainActor
@Test func parameterGroupsHoldEveryParameterOnce() {
    let groups = PBRParameters.Group.allCases
    #expect(groups.flatMap { PBRParameters.scalars(in: $0) }.map(\.name).sorted() == PBRParameters.scalars.map(\.name).sorted())
    #expect(groups.flatMap { PBRParameters.colors(in: $0) }.map(\.name).sorted() == PBRParameters.colors.map(\.name).sorted())
    #expect(groups.flatMap { PBRParameters.toggles(in: $0) }.map(\.name).sorted() == PBRParameters.toggles.map(\.name).sorted())
    #expect(PBRParameters.scalars(in: .base).map(\.name) == ["Metallic", "Roughness", "Emissive Strength"])
}
