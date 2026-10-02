import Foundation

/// A report from a browser extension about one tab's Visio call.
public enum BridgeMessage: Equatable, Sendable {
    case state(tabId: Int, muted: Bool, canUnmute: Bool)
    case bye(tabId: Int)

    private struct Wire: Decodable {
        let type: String
        let tabId: Int
        let muted: Bool?
        let canUnmute: Bool?
    }

    public init?(json: Data) {
        guard let wire = try? JSONDecoder().decode(Wire.self, from: json) else { return nil }
        switch wire.type {
        case "state":
            guard let muted = wire.muted else { return nil }
            self = .state(tabId: wire.tabId, muted: muted, canUnmute: wire.canUnmute ?? false)
        case "bye":
            self = .bye(tabId: wire.tabId)
        default:
            return nil
        }
    }
}

/// What the app asks tabs to do. An unmute is always aimed at exactly one tab.
public enum MuteCommand: Equatable, Sendable {
    case muteAll
    case unmute(CallSessions.Key)

    /// The one channel an unmute goes to; nil = every channel.
    public var channel: Channel? {
        switch self {
        case .muteAll: nil
        case .unmute(let key): key.channel
        }
    }

    /// Wire form for the socket transports.
    public var json: Data {
        switch self {
        case .muteAll: Data(#"{"type":"setMuted","value":true}"#.utf8)
        case .unmute(let key): Data(#"{"type":"setMuted","value":false,"tabId":\#(key.tabId)}"#.utf8)
        }
    }

    /// Same payload for SFSafariApplication.dispatchMessage's userInfo.
    public var userInfo: [String: Any] {
        switch self {
        case .muteAll: ["type": "setMuted", "value": true]
        case .unmute(let key): ["type": "setMuted", "value": false, "tabId": key.tabId]
        }
    }
}
