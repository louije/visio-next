/// Where the calls stand. One value drives both what the menu item says and what the
/// hotkey / menu bar mic do, so they can't disagree.
public enum MuteState: Equatable, Sendable {
    /// At least one call is live: mute them all.
    case mute(calls: Int)
    /// One call, muted, and it may unmute.
    case unmute(CallSessions.Key)
    /// One call, muted, but Visio won't let it publish its microphone.
    case unmuteNotAllowed
    /// Several calls, all muted: no telling which one to unmute.
    case cannotUnmuteSeveral(calls: Int)
}

/// What the hotkey and the menu bar mic do. Muting is the safe, always-available
/// direction; unmuting only happens when there's no doubt which call it's for.
public enum MutePolicy {
    /// nil when there is no call.
    public static func state(for sessions: CallSessions) -> MuteState? {
        let all = sessions.sessions
        if all.isEmpty { return nil }
        if all.values.contains(where: { !$0.muted }) { return .mute(calls: all.count) }
        guard all.count == 1, let (key, session) = all.first else { return .cannotUnmuteSeveral(calls: all.count) }
        return session.canUnmute ? .unmute(key) : .unmuteNotAllowed
    }

    public static func command(for sessions: CallSessions) -> MuteCommand? {
        switch state(for: sessions) {
        case .mute: .muteAll
        case .unmute(let key): .unmute(key)
        case .unmuteNotAllowed, .cannotUnmuteSeveral, nil: nil
        }
    }
}
