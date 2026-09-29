/// What the hotkey and the menu bar mic do. Muting is the safe, always-available
/// direction; unmuting only happens when there's no doubt which call it's for.
public enum MutePolicy {
    public static func command(for sessions: CallSessions) -> MuteCommand? {
        let all = sessions.sessions
        if all.isEmpty { return nil }
        if all.values.contains(where: { !$0.muted }) { return .muteAll }
        if all.count == 1, let (key, session) = all.first, session.canUnmute { return .unmute(key) }
        return nil
    }
}
