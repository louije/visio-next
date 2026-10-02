import Foundation

/// What the app asks tabs to do. An unmute is always aimed at exactly one tab.
public enum MuteCommand: Equatable, Sendable {
    case muteAll
    case unmute(CallSessions.Key)

    /// Where a command goes: some of the open pipe connections, and maybe Safari.
    public struct Targets: Equatable, Sendable {
        public var pipes: Set<Int>
        public var safari: Bool

        public init(pipes: Set<Int>, safari: Bool) {
            self.pipes = pipes
            self.safari = safari
        }
    }

    /// A mute goes to every pipe (a browser may hold calls it hasn't reported yet) and to
    /// Safari if it has a call; an unmute only down its one session's channel. Never to
    /// Safari unless it runs: `dispatchMessage` would launch it.
    public func targets(pipes: Set<Int>, safariHasSession: Bool, safariRunning: Bool) -> Targets {
        switch self {
        case .muteAll:
            Targets(pipes: pipes, safari: safariHasSession && safariRunning)
        case .unmute(let key):
            switch key.channel {
            case .safari: Targets(pipes: [], safari: safariRunning)
            case .pipe(let id): Targets(pipes: pipes.intersection([id]), safari: false)
            }
        }
    }

    /// The payload, as SFSafariApplication.dispatchMessage takes it.
    public var userInfo: [String: Any] {
        switch self {
        case .muteAll: ["type": "setMuted", "value": true]
        case .unmute(let key): ["type": "setMuted", "value": false, "tabId": key.tabId]
        }
    }

    /// The same payload for the socket transports.
    public var json: Data {
        // A string, a bool and an int: always valid JSON.
        try! JSONSerialization.data(withJSONObject: userInfo, options: .sortedKeys)
    }
}
