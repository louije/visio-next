import Testing
import Foundation
import os
@testable import VisioCore

// The bridge's transport on real sockets (helpers in SocketTestSupport).

/// A transport serving two fresh socket paths, and every event it reported.
@MainActor
private final class Harness {
    let safariPath = socketPath()
    let pipePath = socketPath()
    let transport: SocketBridgeTransport
    var events: [BridgeEvent] = []

    init() {
        transport = SocketBridgeTransport(safariSocketPath: safariPath, pipeSocketPath: pipePath,
                                          log: Logger(subsystem: "com.meidosem.visionext.tests", category: "bridge"))
        transport.onEvent = { [weak self] in self?.events.append($0) }
        transport.start()
    }

    isolated deinit {
        unlink(safariPath)
        unlink(pipePath)
    }
}

private func frame(_ json: String) -> Data {
    BridgeFrame.encode(Data(json.utf8))
}

@Test @MainActor func eachPipeConnectionIsItsOwnChannel() async throws {
    let h = Harness()
    let a = try connectClient(to: h.pipePath)
    defer { close(a) }
    #expect(await eventually { h.transport.pipes == [1] })
    let b = try connectClient(to: h.pipePath)
    defer { close(b) }
    #expect(await eventually { h.transport.pipes == [1, 2] })

    send(frame(#"{"type":"state","tabId":7,"muted":false,"canUnmute":true}"#), on: b)
    #expect(await eventually { !h.events.isEmpty })
    #expect(h.events == [.message(.pipe(2), .state(tabId: 7, muted: false, canUnmute: true))])
}

@Test @MainActor func aClosedPipeIsReported() async throws {
    let h = Harness()
    let client = try connectClient(to: h.pipePath)
    #expect(await eventually { h.transport.pipes == [1] })
    close(client)
    #expect(await eventually { h.events == [.closed(.pipe(1))] })
    #expect(h.transport.pipes.isEmpty)
}

@Test @MainActor func safariOneShotMessagesArriveWithoutAClose() async throws {
    let h = Harness()
    for tabId in [1, 2] {
        let client = try connectClient(to: h.safariPath)
        send(frame(#"{"type":"bye","tabId":\#(tabId)}"#), on: client)
        close(client)
    }
    #expect(await eventually { h.events.count == 2 })
    try? await Task.sleep(for: .milliseconds(50))   // a close would have been reported by now
    #expect(h.events == [.message(.safari, .bye(tabId: 1)), .message(.safari, .bye(tabId: 2))])
    #expect(h.transport.pipes.isEmpty)
}

@Test @MainActor func sendWritesDownThatPipeOnly() async throws {
    let h = Harness()
    let a = try connectClient(to: h.pipePath)
    defer { close(a) }
    #expect(await eventually { h.transport.pipes == [1] })
    let b = try connectClient(to: h.pipePath)
    defer { close(b) }
    #expect(await eventually { h.transport.pipes == [1, 2] })

    let command = frame(#"{"type":"setMuted","value":true}"#)
    h.transport.send(command, toPipe: 2)
    #expect(receive(command.count, on: b) == command)
    var poller = pollfd(fd: a, events: Int16(POLLIN), revents: 0)
    #expect(poll(&poller, 1, 50) == 0)
}

@Test @MainActor func unrecognizedMessagesAreSkipped() async throws {
    let h = Harness()
    let client = try connectClient(to: h.pipePath)
    defer { close(client) }
    send(frame(#"{"type":"hello","tabId":1}"#) + frame(#"{"type":"bye","tabId":1}"#), on: client)
    #expect(await eventually { !h.events.isEmpty })
    #expect(h.events == [.message(.pipe(1), .bye(tabId: 1))])
}

@Test @MainActor func anOversizedFrameDropsThePipe() async throws {
    let h = Harness()
    let client = try connectClient(to: h.pipePath)
    defer { close(client) }
    send(Data([0xFF, 0xFF, 0xFF, 0x7F]), on: client)
    #expect(await eventually { h.events == [.closed(.pipe(1))] })
}
