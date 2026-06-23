import SwiftUI
import AppKit
import VisioCore

@main
struct VisioNextApp: App {
    @StateObject private var vm = MenuBarViewModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(vm: vm)
        } label: {
            // Normal: monochrome template glyph (auto-tinted to the menu bar).
            // Imminent: switches to the user's chosen color (or the bicolor brand glyph).
            Image(nsImage: MenuBarIcon.image(imminent: vm.isImminent, color: vm.imminentColor))
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView { vm.reloadSettings() }
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
