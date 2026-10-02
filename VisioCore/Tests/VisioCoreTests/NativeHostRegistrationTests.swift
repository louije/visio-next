import Testing
import Foundation
@testable import VisioCore

/// A fake ~/Library/Application Support with Chrome and Firefox installed, nothing else.
private func supportFolder() throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("vn-support-\(UUID().uuidString)")
    for browser in ["Google/Chrome", "Mozilla"] {
        try FileManager.default.createDirectory(at: root.appendingPathComponent(browser),
                                                withIntermediateDirectories: true)
    }
    return root
}

@discardableResult
private func install(_ script: String, in support: URL) -> [URL] {
    NativeHostRegistration.install(scriptPath: script, supportFolder: support,
                                   chromeExtensionIDs: ["abc"], firefoxExtensionID: "x@y")
}

private func manifest(_ browser: String, in support: URL) -> URL {
    support.appendingPathComponent("\(browser)/NativeMessagingHosts/com.meidosem.visionext.json")
}

private func scriptPath(in manifest: URL) -> String? {
    let data = (try? Data(contentsOf: manifest)) ?? Data()
    return ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["path"] as? String
}

@Test func writesOnlyIntoInstalledBrowsers() throws {
    let support = try supportFolder()
    defer { try? FileManager.default.removeItem(at: support) }

    let written = install("/A/visionext-bridge", in: support)
    #expect(Set(written.map(\.path)) == [manifest("Google/Chrome", in: support).path,
                                        manifest("Mozilla", in: support).path])
    #expect(!FileManager.default.fileExists(atPath: support.appendingPathComponent("Chromium").path))
}

@Test func createsTheHostsFolderWhenMissing() throws {
    let support = try supportFolder()
    defer { try? FileManager.default.removeItem(at: support) }

    install("/A/visionext-bridge", in: support)
    #expect(scriptPath(in: manifest("Google/Chrome", in: support)) == "/A/visionext-bridge")
    #expect(scriptPath(in: manifest("Mozilla", in: support)) == "/A/visionext-bridge")
}

@Test func leavesUpToDateManifestsAlone() throws {
    let support = try supportFolder()
    defer { try? FileManager.default.removeItem(at: support) }

    install("/A/visionext-bridge", in: support)
    #expect(install("/A/visionext-bridge", in: support).isEmpty)
}

@Test func rewritesWhenTheAppMoves() throws {
    let support = try supportFolder()
    defer { try? FileManager.default.removeItem(at: support) }

    install("/A/visionext-bridge", in: support)
    #expect(install("/B/visionext-bridge", in: support).count == 2)
    #expect(scriptPath(in: manifest("Google/Chrome", in: support)) == "/B/visionext-bridge")
    #expect(scriptPath(in: manifest("Mozilla", in: support)) == "/B/visionext-bridge")
}
