import SwiftUI
import AppKit

@main
struct VisioNextApp: App {
    @StateObject private var vm = MenuBarViewModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(vm: vm)
        } label: {
            // Custom visio glyph: template (auto-tinted to the menu bar) normally,
            // tinted (and pulsing) when a meeting with a link is imminent.
            Image(nsImage: MenuBarIcon.image(imminent: vm.isImminent, pulse: vm.pulse))
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView { vm.reloadSettings() }
        }
    }
}

enum MenuBarIcon {
    private static let pointSize = NSSize(width: 18, height: 18)

    /// Tint used for the "imminent" state. Swap to taste, e.g.:
    /// `.systemRed`, `.systemOrange`, `.systemPink`, `.controlAccentColor`.
    static let imminentColor: NSColor = .systemRed

    /// Faintest opacity reached at the bottom of a pulse (1 = no fade).
    private static let pulseMinOpacity: CGFloat = 0.35

    /// - Parameter pulse: 0…1 phase from the view model; 1 = full intensity.
    static func image(imminent: Bool, pulse: Double = 1) -> NSImage {
        let base = NSImage(named: "VisioIcon")
            ?? NSImage(systemSymbolName: "video", accessibilityDescription: "visio-next")!
        let rect = NSRect(origin: .zero, size: pointSize)

        guard imminent else {
            let template = base.copy() as! NSImage
            template.size = pointSize
            template.isTemplate = true
            return template
        }

        // Fully-tinted glyph (non-template so the color shows).
        let solid = NSImage(size: pointSize)
        solid.lockFocus()
        base.draw(in: rect)
        imminentColor.set()
        rect.fill(using: .sourceAtop)
        solid.unlockFocus()

        // Composite it at the pulse opacity so the icon visibly breathes.
        let opacity = pulseMinOpacity + (1 - pulseMinOpacity) * CGFloat(pulse)
        let out = NSImage(size: pointSize)
        out.lockFocus()
        solid.draw(in: rect, from: rect, operation: .sourceOver, fraction: opacity)
        out.unlockFocus()
        out.isTemplate = false
        return out
    }
}
