/// What the hotkey and the menu bar mic do. Muting is the safe, always-available
/// direction; unmuting only happens when there's no doubt which call it's for.
public enum MutePolicy {
    public static func command(for sessions: CallSessions) -> MuteCommand? {
        let all = Array(sessions.sessions.values)
        if all.isEmpty { return nil }
        if all.contains(where: { !$0.muted }) { return .setMuted(true) }
        if all.count == 1, all[0].canUnmute { return .setMuted(false) }
        return nil
    }
}
