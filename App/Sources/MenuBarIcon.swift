import AppKit
import VisioCore

/// The VisioNext glyph in the menu bar (MenuBarExtra's label).
enum MenuBarIcon {
    private static let pointSize = NSSize(width: 18, height: 18)

    static func image(imminent: Bool, color: IconColor) -> NSImage {
        let base = NSImage(named: "VisioIcon")
            ?? NSImage(systemSymbolName: "video", accessibilityDescription: "visio-next")!
        let rect = NSRect(origin: .zero, size: pointSize)

        guard imminent else {
            let template = base.copy() as! NSImage
            template.size = pointSize
            template.isTemplate = true
            return template
        }

        // Bicolor: the two-tone brand glyph, shown in its own colors.
        if color == .bicolor, let brand = NSImage(named: "VisioIconColor") {
            let out = (brand.copy() as! NSImage)
            out.size = pointSize
            out.isTemplate = false
            return out
        }

        // Solid tint: fill the glyph with the chosen color (non-template so it shows).
        return tinted(size: pointSize, color: color) { base.draw(in: rect) }
    }

    /// Draws `content` and fills it with `color`, baked in now (non-template), so every
    /// tinted icon (glyph, live mic) resolves the color the same way.
    static func tinted(size: NSSize, color: IconColor, content: () -> Void) -> NSImage {
        let out = NSImage(size: size)
        out.lockFocus()
        content()
        nsColor(for: color).set()
        NSRect(origin: .zero, size: size).fill(using: .sourceAtop)
        out.unlockFocus()
        out.isTemplate = false
        return out
    }

    static func nsColor(for color: IconColor) -> NSColor {
        switch color {
        case .white: return .white
        case .red: return .systemRed
        case .orange: return .systemOrange
        case .pink: return NSColor(srgbRed: 1.0, green: 0.18, blue: 0.60, alpha: 1)
        case .green: return .systemGreen
        case .blue: return .systemBlue
        case .bicolor: return .systemRed  // the live mic; the glyph keeps its own two tones
        }
    }
}

/// The mic next to it during a call (MicStatusItem).
enum MicIcon {
    /// Same height as the VisioNext glyph (MenuBarIcon), so both items share a baseline.
    private static let height: CGFloat = 18
    /// The mic's stand makes it look high when centred; nudge it down to line up with the glyph.
    private static let drop: CGFloat = 0.5

    static func image(live: Bool, color: IconColor) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        guard let symbol = NSImage(systemSymbolName: live ? "mic.fill" : "mic.slash.fill",
                                   accessibilityDescription: live ? "Micro actif" : "Micro coupé")?
            .withSymbolConfiguration(config) else { return nil }
        let s = symbol.size
        let size = NSSize(width: s.width, height: height)
        let draw = { symbol.draw(in: NSRect(x: 0, y: (height - s.height) / 2 - drop, width: s.width, height: s.height)) }
        // Live: tinted exactly like the imminent glyph (same color resolution); muted: template.
        let image: NSImage
        if live {
            image = MenuBarIcon.tinted(size: size, color: color, content: draw)
        } else {
            image = NSImage(size: size, flipped: false) { _ in draw(); return true }
            image.isTemplate = true
        }
        image.accessibilityDescription = symbol.accessibilityDescription
        return image
    }
}
