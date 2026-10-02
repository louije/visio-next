import VisioCore

/// How the global mute's state reads in the menu and on the mic status item.
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

    /// The action mutes: at least one call is live.
    var isMute: Bool {
        if case .mute = self { return true }
        return false
    }
}
