import AppKit
import VisioCore

/// The mic next to the VisioNext icon, shown only during a call. A separate status item
/// because since macOS 27 the system menu bar handles clicks on MenuBarExtra's item and
/// never tells the app where the click landed, so one icon can't have two click targets.
///
/// Created once at launch, right after MenuBarExtra's item, so it sits next to it; it is
/// only shown and hidden afterwards, which keeps its place in the menu bar.
@MainActor
final class MicStatusItem: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let onClick: () -> Void

    init(onClick: @escaping () -> Void) {
        self.onClick = onClick
        super.init()
        item.autosaveName = "mic"
        item.isVisible = false
        item.button?.target = self
        item.button?.action = #selector(clicked)
    }

    /// Live: mic in the "hot" color; muted: default slashed mic; no call: hidden.
    func update(state: MuteState?, indicator: CallIndicator, color: IconColor) {
        item.isVisible = indicator != .none
        guard indicator != .none, let button = item.button else { return }
        button.image = MicIcon.image(live: indicator == .live, color: color)
        button.toolTip = state?.title
    }

    @objc private func clicked() {
        onClick()
    }
}

enum MicIcon {
    /// Same height as the VisioNext glyph (MenuBarIcon), so both items share a baseline.
    private static let height: CGFloat = 18
    /// The mic's stand makes it look high when centred; nudge it down to line up with the glyph.
    private static let drop: CGFloat = 2

    static func image(live: Bool, color: IconColor) -> NSImage? {
        var config = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        if live {
            config = config.applying(NSImage.SymbolConfiguration(paletteColors: [MenuBarIcon.nsColor(for: color)]))
        }
        guard let symbol = NSImage(systemSymbolName: live ? "mic.fill" : "mic.slash.fill",
                                   accessibilityDescription: live ? "Micro actif" : "Micro coupé")?
            .withSymbolConfiguration(config) else { return nil }
        let s = symbol.size
        let image = NSImage(size: NSSize(width: s.width, height: height), flipped: false) { _ in
            symbol.draw(in: NSRect(x: 0, y: (height - s.height) / 2 - drop, width: s.width, height: s.height))
            return true
        }
        image.accessibilityDescription = symbol.accessibilityDescription
        image.isTemplate = !live
        return image
    }
}

extension MuteState {
    /// What the menu item (and the mic's tooltip) says.
    var title: String {
        switch self {
        case .mute(1): "Couper le micro"
        case .mute(let calls): "Couper le micro (\(calls) visios)"
        case .unmute: "Réactiver le micro"
        case .unmuteNotAllowed: "Micro non autorisé dans cette visio"
        case .cannotUnmuteSeveral: "Impossible de réactiver plusieurs visios"
        }
    }

    var isActionable: Bool {
        switch self {
        case .mute, .unmute: true
        case .unmuteNotAllowed, .cannotUnmuteSeveral: false
        }
    }
}
