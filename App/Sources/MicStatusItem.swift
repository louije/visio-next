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
