import Foundation

/// What the browser side of the bridge reports.
public enum BridgeEvent: Equatable, Sendable {
    case message(Channel, BridgeMessage)
    /// A channel's connection is gone, and with it every call it reported.
    case closed(Channel)
}

/// How `CallBridge` hears from the extensions and talks back to the pipe ones. A protocol
/// so a preview (or a test) can run the bridge without opening sockets.
@MainActor
public protocol BridgeTransport: AnyObject {
    var onEvent: ((BridgeEvent) -> Void)? { get set }
    /// The pipe connections open right now, by the number in their `.pipe` channel.
    var pipes: Set<Int> { get }
    func start()
    func send(_ frame: Data, toPipe id: Int)
}
