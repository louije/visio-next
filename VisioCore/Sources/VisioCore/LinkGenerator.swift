import Foundation

public enum LinkGenerator {
    static let randomCharset = Array("abcdefghijklmnopqrstuvwxyz0123456789")

    /// Builds a link: each block is its literal `value`, or `length` random
    /// `[a-z0-9]` characters when `value` is empty; blocks joined with "-" and
    /// prefixed by `baseURL`. RNG is injected so callers (and tests) control randomness.
    public static func generate<G: RandomNumberGenerator>(from template: LinkTemplate,
                                                          using rng: inout G) -> String {
        let parts = template.blocks.map { block in
            block.value.isEmpty ? randomString(length: block.length, using: &rng) : block.value
        }
        return template.baseURL + parts.joined(separator: "-")
    }

    private static func randomString<G: RandomNumberGenerator>(length: Int,
                                                              using rng: inout G) -> String {
        guard length > 0 else { return "" }
        return String((0..<length).map { _ in randomCharset.randomElement(using: &rng)! })
    }
}
