import Testing
@testable import VisioCore

/// Tiny deterministic RNG so generation is reproducible in tests.
private struct SeededRNG: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}

private let charset = Set("abcdefghijklmnopqrstuvwxyz0123456789")

@Test func literalBlocksAreUsedVerbatim() {
    let template = LinkTemplate(baseURL: "https://x.test/",
                                blocks: [LinkBlock(length: 3, value: "pdi"),
                                         LinkBlock(length: 3, value: "abc"),
                                         LinkBlock(length: 3, value: "ljt")])
    var rng = SeededRNG(seed: 1)
    #expect(LinkGenerator.generate(from: template, using: &rng) == "https://x.test/pdi-abc-ljt")
}

@Test func emptyBlocksBecomeRandomOfCorrectLengthAndCharset() {
    let template = LinkTemplate(baseURL: "https://visio.numerique.gouv.fr/",
                                blocks: [LinkBlock(length: 3, value: "pdi"),
                                         LinkBlock(length: 4),
                                         LinkBlock(length: 3, value: "ljt")])
    var rng = SeededRNG(seed: 42)
    let link = LinkGenerator.generate(from: template, using: &rng)

    #expect(link.hasPrefix("https://visio.numerique.gouv.fr/"))
    let slug = String(link.dropFirst("https://visio.numerique.gouv.fr/".count))
    let parts = slug.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
    #expect(parts.count == 3)
    #expect(parts[0] == "pdi")
    #expect(parts[2] == "ljt")
    #expect(parts[1].count == 4)
    #expect(parts[1].allSatisfy { charset.contains($0) })
}

@Test func sameSeedProducesSameLink() {
    let template = LinkTemplate.default
    var a = SeededRNG(seed: 7)
    var b = SeededRNG(seed: 7)
    #expect(LinkGenerator.generate(from: template, using: &a)
            == LinkGenerator.generate(from: template, using: &b))
}
