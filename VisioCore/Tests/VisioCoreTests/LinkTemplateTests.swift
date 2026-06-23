import Testing
import Foundation
@testable import VisioCore

@Test func defaultTemplateIsGouvBaseWithTenBlankSlots() {
    let t = LinkTemplate.default
    #expect(t.baseURL == "https://visio.numerique.gouv.fr/")
    #expect(t.mask.count == 10)
    #expect(t.mask.allSatisfy { $0.isEmpty })
    #expect(LinkTemplate.groups == [3, 4, 3])
}

@Test func initNormalizesMaskToTenSingleCharSlots() {
    // Too few, multi-char slots → padded to 10, each at most one character.
    let t = LinkTemplate(baseURL: "https://x.test/", mask: ["pd", "i"])
    #expect(t.mask.count == 10)
    #expect(t.mask[0] == "d")   // suffix(1) of "pd"
    #expect(t.mask[1] == "i")
    #expect(t.mask[2] == "")
}

@Test func migratesOldBlocksShapeToMask() throws {
    let json = """
    {"baseURL":"https://x.test/","blocks":[{"length":3,"value":"pdi"},{"length":4,"value":""},{"length":3,"value":"ljt"}]}
    """.data(using: .utf8)!
    let t = try JSONDecoder().decode(LinkTemplate.self, from: json)
    #expect(t.baseURL == "https://x.test/")
    #expect(t.mask == ["p", "d", "i", "", "", "", "", "l", "j", "t"])
}
