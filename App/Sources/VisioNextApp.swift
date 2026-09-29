import SwiftUI
import AppKit
import VisioCore
import MenuBarExtraAccess

@main
struct VisioNextApp: App {
    @StateObject private var vm = MenuBarViewModel()
    @StateObject private var updater = UpdaterViewModel()
    @StateObject private var bridge = CallBridge()
    @State private var isMenuPresented = false

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(vm: vm)
        } label: {
            // Normal: monochrome template glyph (auto-tinted to the menu bar).
            // Imminent: switches to the user's chosen color (or the bicolor brand glyph).
            // In a call: mic + glyph; clicking the mic part mutes (MicClickInterceptor).
            Image(nsImage: MenuBarIcon.image(imminent: vm.isImminent, color: vm.imminentColor,
                                             call: bridge.sessions.indicator))
        }
        .menuBarExtraAccess(isPresented: $isMenuPresented) { statusItem in
            bridge.attach(statusItem: statusItem)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(updater: updater) { vm.reloadSettings() }
        }
    }
}

enum MenuBarIcon {
    private static let pointSize = NSSize(width: 18, height: 18)
    private static let micSize = NSSize(width: 16, height: 18)
    private static let gap: CGFloat = 4

    /// Width of the clickable mic part (mic + half the gap), measured from the image's left edge.
    static let micSegmentWidth = micSize.width + gap / 2

    static func image(imminent: Bool, color: IconColor, call: CallIndicator) -> NSImage {
        // In a call the imminent tint has done its job; show mic + glyph, both template.
        if call != .none { return callImage(muted: call == .muted) }
        return glyphImage(imminent: imminent, color: color)
    }

    private static func callImage(muted: Bool) -> NSImage {
        let glyph = glyphImage(imminent: false, color: .white)
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        let mic = NSImage(systemSymbolName: muted ? "mic.slash.fill" : "mic.fill",
                          accessibilityDescription: muted ? "Micro coupé" : "Micro actif")?
            .withSymbolConfiguration(config)
        let size = NSSize(width: micSize.width + gap + pointSize.width, height: pointSize.height)
        let out = NSImage(size: size, flipped: false) { _ in
            if let mic {
                let m = mic.size
                mic.draw(in: NSRect(x: (micSize.width - m.width) / 2, y: (micSize.height - m.height) / 2,
                                    width: m.width, height: m.height))
            }
            glyph.draw(in: NSRect(origin: NSPoint(x: micSize.width + gap, y: 0), size: pointSize))
            return true
        }
        out.isTemplate = true
        return out
    }

    private static func glyphImage(imminent: Bool, color: IconColor) -> NSImage {
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
        let out = NSImage(size: pointSize)
        out.lockFocus()
        base.draw(in: rect)
        nsColor(for: color).set()
        rect.fill(using: .sourceAtop)
        out.unlockFocus()
        out.isTemplate = false
        return out
    }

    private static func nsColor(for color: IconColor) -> NSColor {
        switch color {
        case .white: return .white
        case .red: return .systemRed
        case .orange: return .systemOrange
        case .pink: return NSColor(srgbRed: 1.0, green: 0.18, blue: 0.60, alpha: 1)
        case .green: return .systemGreen
        case .blue: return .systemBlue
        case .bicolor: return .systemRed  // unused (handled above)
        }
    }
}
