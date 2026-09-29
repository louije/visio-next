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
            self = .state(tabId: wire.tabId, muted: muted, canUnmute: wire.canUnmute ?? true)
        case "bye":
            self = .bye(tabId: wire.tabId)
        default:
            return nil
        }
    }
}

/// What the app asks every tab to do.
public enum MuteCommand: Equatable, Sendable {
    case setMuted(Bool)

    /// Wire form for the socket transports.
    public var json: Data {
        switch self {
        case .setMuted(let value): Data(#"{"type":"setMuted","value":\#(value)}"#.utf8)
        }
    }
}
