import SafariServices

/// Principal class for the bundled Safari Web Extension.
///
/// The extension's background opens `browser.runtime.connectNative(...)`; every message
/// it posts on that port arrives here. They are call reports for the global mute, so the
/// handler forwards each one to the running app over its socket. (The way back is
/// `SFSafariApplication.dispatchMessage`, called by the app.)
final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
        let item = context.inputItems.first as? NSExtensionItem
        if let message = item?.userInfo?[SFExtensionMessageKey],
           JSONSerialization.isValidJSONObject(message),
           let json = try? JSONSerialization.data(withJSONObject: message) {
            BridgeClient.send(json)
        }
        context.completeRequest(returningItems: [NSExtensionItem()], completionHandler: nil)
    }
}
