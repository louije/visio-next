import Testing
import Foundation
import os
@testable import VisioCore

// Real sockets, served on the main queue as in the app (helpers in SocketTestSupport).

private let log = Logger(subsystem: "com.meidosem.visionext.tests", category: "socket")

/// What a server saw, fed through `BridgeFrame.Decoder` like the bridge does.
@MainActor
private final class Recorder {
    var connections: [UnixSocketConnection] = []
    var chunks: [Data] = []
    var messages: [Data] = []
    var closes = 0
    private var decoder = BridgeFrame.Decoder()

    func accept(_ connection: UnixSocketConnection) {
        connections.append(connection)
        // Weak: a connection outlives its test until the client's close reaches it.
        connection.onData = { [weak self] data in
            guard let self else { return }
            chunks.append(data)
            messages += (try? decoder.feed(data)) ?? []
        }
        connection.onClose = { [weak self] in self?.closes += 1 }
    }
}

@MainActor
private func serve(_ path: String, _ recorder: Recorder) -> UnixSocketServer {
    UnixSocketServer(path: path, log: log) { recorder.accept($0) }
}

private let frame = BridgeFrame.encode(Data(#"{"type":"bye","tabId":1}"#.utf8))

@Test @MainActor func oneShotClientIsDelivered() async throws {
    let path = socketPath()
    let recorder = Recorder()
    let server = serve(path, recorder)
    #expect(server.start())
    defer { server.stop(); unlink(path) }

    // Safari's appex: connect, write, close, all before the server gets to accept.
    let client = try connectClient(to: path)
    send(frame, on: client)
    close(client)

    #expect(await eventually { recorder.closes == 1 })
    #expect(recorder.messages == [frame.dropFirst(4)])
}

@Test @MainActor func longLivedClientReceivesServerWrite() async throws {
    let path = socketPath()
    let recorder = Recorder()
    let server = serve(path, recorder)
    #expect(server.start())
    defer { server.stop(); unlink(path) }

    let client = try connectClient(to: path)
    defer { close(client) }
    #expect(await eventually { recorder.connections.count == 1 })
    recorder.connections[0].write(frame)
    #expect(receive(frame.count, on: client) == frame)
    #expect(recorder.closes == 0)
}

@Test @MainActor func writingToAPeerThatClosedDropsTheConnection() async throws {
    // SIGPIPE deliberately not ignored here: a regression to plain write() kills the run.
    let path = socketPath()
    let recorder = Recorder()
    let server = serve(path, recorder)
    #expect(server.start())
    defer { server.stop(); unlink(path) }

    // Closed after the accept: the write gets EPIPE before the read source sees the EOF.
    let late = try connectClient(to: path)
    #expect(await eventually { recorder.connections.count == 1 })
    close(late)
    recorder.connections[0].write(frame)
    #expect(recorder.closes == 1)

    // Closed before the accept (the crash this guards against): write as soon as accepted.
    var wroteOnAccept = false
    let eager = UnixSocketServer(path: path + "2", log: log) { connection in
        recorder.accept(connection)
        connection.write(frame)
        wroteOnAccept = true
    }
    #expect(eager.start())
    defer { eager.stop(); unlink(path + "2") }
    close(try connectClient(to: path + "2"))
    #expect(await eventually { wroteOnAccept })
    #expect(recorder.closes == 2)
}

@Test @MainActor func secondServerRefusesAPathALiveServerOwns() async throws {
    let path = socketPath()
    let recorder = Recorder()
    let first = serve(path, recorder)
    #expect(first.start())
    defer { first.stop(); unlink(path) }

    let second = serve(path, Recorder())
    #expect(!second.start())

    // The first still serves the path (the second didn't unlink it).
    let client = try connectClient(to: path)
    defer { close(client) }
    #expect(await eventually { recorder.connections.count == 2 })   // the probe, then the client
}

@Test @MainActor func staleSocketFileIsReclaimed() async throws {
    let path = socketPath()
    // A socket file nobody listens on, as a crashed run leaves behind.
    var address = try #require(BridgeEndpoint.address(for: path))
    let stale = socket(AF_UNIX, SOCK_STREAM, 0)
    let bound = withUnsafePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            bind(stale, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
    }
    close(stale)
    #expect(bound == 0 && FileManager.default.fileExists(atPath: path))

    let recorder = Recorder()
    let server = serve(path, recorder)
    #expect(server.start())
    defer { server.stop(); unlink(path) }
    let client = try connectClient(to: path)
    defer { close(client) }
    #expect(await eventually { recorder.connections.count == 1 })
}

@Test @MainActor func onCloseFiresExactlyOnce() async throws {
    let path = socketPath()
    let recorder = Recorder()
    let server = serve(path, recorder)
    #expect(server.start())
    defer { server.stop(); unlink(path) }

    let client = try connectClient(to: path)
    #expect(await eventually { recorder.connections.count == 1 })
    close(client)
    #expect(await eventually { recorder.closes == 1 })

    let connection = recorder.connections[0]
    connection.close()
    connection.write(frame)
    try? await Task.sleep(for: .milliseconds(50))
    #expect(recorder.closes == 1)
}

@Test @MainActor func framesSplitAcrossReadsDecode() async throws {
    let path = socketPath()
    let recorder = Recorder()
    let server = serve(path, recorder)
    #expect(server.start())
    defer { server.stop(); unlink(path) }

    let client = try connectClient(to: path)
    defer { close(client) }
    send(frame.prefix(6), on: client)   // the header and two bytes of the body
    #expect(await eventually { recorder.chunks.count == 1 })
    #expect(recorder.messages.isEmpty)

    send(frame.dropFirst(6), on: client)
    #expect(await eventually { recorder.messages.count == 1 })
    #expect(recorder.messages == [frame.dropFirst(4)])
}
