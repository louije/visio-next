import Testing
@testable import VisioCore

@Test func defaultTemplateIsGouvBaseWithThreeBlankBlocks() {
    let t = LinkTemplate.default
    #expect(t.baseURL == "https://visio.numerique.gouv.fr/")
    #expect(t.blocks.map(\.length) == [3, 4, 3])
    #expect(t.blocks.allSatisfy { $0.value.isEmpty })
}
