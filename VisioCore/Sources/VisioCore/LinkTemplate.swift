import Foundation

/// One segment of a generated link. An empty `value` means "generate `length`
/// random characters"; a non-empty `value` is used literally.
public struct LinkBlock: Codable, Equatable, Sendable {
    public var length: Int
    public var value: String

    public init(length: Int, value: String = "") {
        self.length = length
        self.value = value
    }
}

/// A visio link is `baseURL` followed by the blocks joined with "-".
public struct LinkTemplate: Codable, Equatable, Sendable {
    public var baseURL: String
    public var blocks: [LinkBlock]

    public init(baseURL: String, blocks: [LinkBlock]) {
        self.baseURL = baseURL
        self.blocks = blocks
    }

    public static let `default` = LinkTemplate(
        baseURL: "https://visio.numerique.gouv.fr/",
        blocks: [LinkBlock(length: 3), LinkBlock(length: 4), LinkBlock(length: 3)]
    )
}
