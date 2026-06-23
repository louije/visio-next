import Foundation

public enum LinkGenerator {
    static let randomCharset = Array("abcdefghijklmnopqrstuvwxyz0123456789")

    /// Builds a link from the template's character mask: each slot is its literal
    /// character, or a random `[a-z0-9]` character when empty. The resulting characters
    /// are grouped per `LinkTemplate.groups`, joined with "-", and prefixed by `baseURL`.
    /// RNG is injected so callers (and tests) control randomness.
    public static func generate<G: RandomNumberGenerator>(from template: LinkTemplate,
                                                          using rng: inout G) -> String {
        let chars: [Character] = template.mask.map { slot in
            slot.first ?? randomCharset.randomElement(using: &rng)!
        }

        var groups: [String] = []
        var index = 0
        for size in LinkTemplate.groups {
            let end = min(index + size, chars.count)
            groups.append(String(chars[index..<end]))
            index = end
        }
        return template.baseURL + groups.joined(separator: "-")
    }
}
