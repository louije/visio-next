import Foundation

/// Where a report came from: the Safari appex, or one Chrome/Firefox pipe connection
/// (numbered by the app, since tab ids are only unique within one browser).
public enum Channel: Hashable, Sendable {
    case safari
    case pipe(Int)
}

/// One tab's last reported mute state and when we last heard from it.
public struct CallSession: Equatable, Sendable {
    public var muted: Bool
    public var canUnmute: Bool
    public var lastSeen: Date
}

/// The Visio calls the extensions have reported, keyed by channel + tab.
public struct CallSessions: Equatable, Sendable {
    public struct Key: Hashable, Sendable {
        public let channel: Channel
        public let tabId: Int
    }

    /// Extensions heartbeat every 30 s; a session silent for this long is gone.
    public static let timeout: TimeInterval = 90

    public private(set) var sessions: [Key: CallSession] = [:]

    public init() {}

    public mutating func apply(_ message: BridgeMessage, from channel: Channel, at now: Date) {
        switch message {
        case let .state(tabId, muted, canUnmute):
            sessions[Key(channel: channel, tabId: tabId)] = CallSession(muted: muted, canUnmute: canUnmute, lastSeen: now)
        case let .bye(tabId):
            sessions[Key(channel: channel, tabId: tabId)] = nil
        }
    }

    public mutating func drop(channel: Channel) {
        let kept = sessions.filter { $0.key.channel != channel }
        if kept.count != sessions.count { sessions = kept }
    }

    public mutating func expire(now: Date) {
        let kept = sessions.filter { now.timeIntervalSince($0.value.lastSeen) <= Self.timeout }
        if kept.count != sessions.count { sessions = kept }
    }

    public var channels: Set<Channel> { Set(sessions.keys.map(\.channel)) }
}
