import Foundation

/// The JSON file that registers our native-messaging host with a browser.
public enum NativeHostManifest {
    public static let hostName = "com.meidosem.visionext"

    public static func chromium(path: String, extensionIDs: [String]) -> Data {
        encode(base(path: path).merging(
            ["allowed_origins": extensionIDs.map { "chrome-extension://\($0)/" }]) { $1 })
    }

    public static func firefox(path: String, extensionID: String) -> Data {
        encode(base(path: path).merging(["allowed_extensions": [extensionID]]) { $1 })
    }

    private static func base(path: String) -> [String: Any] {
        ["name": hostName, "description": "VisioNext bridge", "path": path, "type": "stdio"]
    }

    private static func encode(_ object: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: object,
                                     options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])) ?? Data()
    }
}
