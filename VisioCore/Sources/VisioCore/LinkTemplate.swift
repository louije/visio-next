import Foundation

/// Template for a generated visio link: a base URL followed by a fixed-shape slug.
/// The slug is `length` characters grouped by `groups` and joined with "-" (3-4-3).
/// Each character in `mask` is either a literal (one character) or "" meaning "random".
public struct LinkTemplate: Codable, Equatable, Sendable {
    /// Structural grouping of the slug, dash-separated. 3-4-3 = 10 characters.
    public static let groups = [3, 4, 3]
    /// Total number of editable characters in the slug.
    public static let length = 10

    public var baseURL: String
    /// Exactly `length` slots; each "" = random `[a-z0-9]`, else a single literal character.
    public var mask: [String]

    public init(baseURL: String, mask: [String]) {
        self.baseURL = baseURL
        self.mask = Self.normalized(mask)
    }

    /// Force `mask` to exactly `length` single-character (or empty) slots.
    private static func normalized(_ mask: [String]) -> [String] {
        var m = mask.map { String($0.suffix(1)) }
        if m.count < length { m += Array(repeating: "", count: length - m.count) }
        return Array(m.prefix(length))
    }

    public static let `default` = LinkTemplate(
        baseURL: "https://visio.numerique.gouv.fr/",
        mask: Array(repeating: "", count: length)
    )
}

// MARK: - Codable (with migration from the old `blocks` shape)

public extension LinkTemplate {
    private enum CodingKeys: String, CodingKey { case baseURL, mask, blocks }

    /// The pre-mask template stored `blocks: [{length, value}]`; decode it for migration.
    private struct LegacyBlock: Decodable { var length: Int; var value: String }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let base = try c.decodeIfPresent(String.self, forKey: .baseURL) ?? LinkTemplate.default.baseURL

        if let mask = try c.decodeIfPresent([String].self, forKey: .mask) {
            self.init(baseURL: base, mask: mask)
        } else if let blocks = try c.decodeIfPresent([LegacyBlock].self, forKey: .blocks) {
            var mask: [String] = []
            for block in blocks {
                let chars = Array(block.value)
                for i in 0..<block.length {
                    mask.append(i < chars.count ? String(chars[i]) : "")
                }
            }
            self.init(baseURL: base, mask: mask)
        } else {
            self.init(baseURL: base, mask: [])
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(baseURL, forKey: .baseURL)
        try c.encode(mask, forKey: .mask)
    }
}
