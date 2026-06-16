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
            // tinted red when a meeting with a link is imminent.
            Image(nsImage: MenuBarIcon.image(imminent: vm.isImminent))
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView { vm.reloadSettings() }
        }
    }
}

enum MenuBarIcon {
    private static let pointSize = NSSize(width: 18, height: 18)

    static func image(imminent: Bool) -> NSImage {
        let base = NSImage(named: "VisioIcon")
            ?? NSImage(systemSymbolName: "video", accessibilityDescription: "visio-next")!

        guard imminent else {
            let template = base.copy() as! NSImage
            template.size = pointSize
            template.isTemplate = true
            return template
        }

        // Draw the glyph filled with the alert color (non-template so the color shows).
        let tinted = NSImage(size: pointSize)
        tinted.lockFocus()
        let rect = NSRect(origin: .zero, size: pointSize)
        base.draw(in: rect)
        NSColor.systemRed.set()
        rect.fill(using: .sourceAtop)
        tinted.unlockFocus()
        tinted.isTemplate = false
        return tinted
    }
}
