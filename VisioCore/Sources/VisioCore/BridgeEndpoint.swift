import Foundation

/// Where the bridge's two sockets live, for the app that serves them and the clients that
/// reach them: the Safari appex, and the native host script (which can't import this, so
/// `App/NativeHost/visionext-bridge` repeats the pipe socket's path).
public enum BridgeEndpoint {
    /// The App Group shared by the app, the widget and the Safari appex (project.yml).
    /// The Safari socket lives in its container, the only place the sandboxed appex can reach.
    public static let appGroupID = "group.com.meidosem.visionext"

    /// The Safari appex's socket; nil if the App Group isn't provisioned.
    public static var safariSocketPath: String? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent("bridge.sock").path
    }

    /// The Chrome/Firefox host's socket. Must match `$(getconf DARWIN_USER_TEMP_DIR)visionext-bridge.sock`
    /// in the host script, hence the same `confstr` rather than `NSTemporaryDirectory()`,
    /// which may differ. Not in the group container: since macOS 15 a process outside the
    /// group touching it gets a prompt.
    public static var pipeSocketPath: String {
        userTempDirectory + "visionext-bridge.sock"
    }

    private static var userTempDirectory: String {
        let size = confstr(_CS_DARWIN_USER_TEMP_DIR, nil, 0)
        if size > 0 {
            var buffer = [CChar](repeating: 0, count: size)
            if confstr(_CS_DARWIN_USER_TEMP_DIR, &buffer, size) > 0 {
                return buffer.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
            }
        }
        return NSTemporaryDirectory()
    }

    /// The `sockaddr_un` for `path`; nil if it doesn't fit `sun_path` (104 bytes with the NUL).
    public static func address(for path: String) -> sockaddr_un? {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = path.utf8CString
        guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { return nil }
        withUnsafeMutableBytes(of: &address.sun_path) { dest in
            bytes.withUnsafeBytes { dest.copyMemory(from: $0) }
        }
        return address
    }
}
