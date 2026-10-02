import SwiftUI
import AppKit
import VisioCore

@main
struct VisioNextApp: App {
    @StateObject private var vm = MenuBarViewModel()
    @StateObject private var updater = UpdaterViewModel()
    @StateObject private var bridge = CallBridge()

    init() {
        // Before any socket exists: a write to a bridge connection whose peer has gone
        // must fail with EPIPE, not kill the app. SO_NOSIGPIPE alone isn't enough, as
        // setsockopt fails on a connection the peer closed before it was accepted.
        signal(SIGPIPE, SIG_IGN)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(vm: vm, bridge: bridge)
        } label: {
            // Normal: monochrome template glyph (auto-tinted to the menu bar).
            // Imminent: switches to the user's chosen color (or the bicolor brand glyph).
            // During a call a separate mic item shows up next to it (MicStatusItem), live
            // mic in the same chosen color.
            Image(nsImage: MenuBarIcon.image(imminent: vm.isImminent, color: vm.imminentColor))
                .onChange(of: vm.imminentColor, initial: true) { bridge.micColor = vm.imminentColor }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(updater: updater) { vm.reloadSettings() }
        }
    }
}

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
