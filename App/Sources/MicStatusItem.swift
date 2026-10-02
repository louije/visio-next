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

    /// Live (a call to mute): mic in the "hot" color; all muted: default slashed mic;
    /// no call: hidden.
    func update(state: MuteState?, color: IconColor) {
        item.isVisible = state != nil
        guard let state, let button = item.button else { return }
        button.image = MicIcon.image(live: state.isMute, color: color)
        button.toolTip = state.title
    }

    @objc private func clicked() {
        onClick()
    }
}
