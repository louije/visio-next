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

@Test func manifestOutputIsStable() {
    // Same input → same bytes, so the installer can skip rewriting unchanged files.
    let a = NativeHostManifest.chromium(path: "/A", extensionIDs: ["abc"])
    let b = NativeHostManifest.chromium(path: "/A", extensionIDs: ["abc"])
    #expect(a == b)
}
