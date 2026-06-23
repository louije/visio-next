import Foundation

/// Color shown by the menu bar icon when a meeting is imminent.
/// `bicolor` uses the two-tone La Suite Visio brand glyph; the rest are solid tints.
public enum IconColor: String, Codable, Sendable, CaseIterable {
    case white, red, pink, green, blue, bicolor
}
