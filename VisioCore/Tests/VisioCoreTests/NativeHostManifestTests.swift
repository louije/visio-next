import Testing
import Foundation
@testable import VisioCore

private func object(_ data: Data) -> [String: Any] {
    (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
}

@Test func chromiumManifestListsAllowedOrigins() {
    let m = object(NativeHostManifest.chromium(path: "/A/visionext-bridge", extensionIDs: ["abc", "def"]))
    #expect(m["name"] as? String == "com.meidosem.visionext")
    #expect(m["path"] as? String == "/A/visionext-bridge")
    #expect(m["type"] as? String == "stdio")
    #expect(m["allowed_origins"] as? [String] == ["chrome-extension://abc/", "chrome-extension://def/"])
    #expect(m["allowed_extensions"] == nil)
}

@Test func firefoxManifestListsAllowedExtensions() {
    let m = object(NativeHostManifest.firefox(path: "/A/visionext-bridge", extensionID: "x@y"))
    #expect(m["allowed_extensions"] as? [String] == ["x@y"])
    #expect(m["allowed_origins"] == nil)
}

/// The installer compares bytes to skip rewriting an unchanged manifest.
@Test func manifestsAreDeterministic() {
    #expect(NativeHostManifest.chromium(path: "/A", extensionIDs: ["abc", "def"])
        == NativeHostManifest.chromium(path: "/A", extensionIDs: ["abc", "def"]))
    #expect(NativeHostManifest.firefox(path: "/A", extensionID: "x@y")
        == NativeHostManifest.firefox(path: "/A", extensionID: "x@y"))
}
