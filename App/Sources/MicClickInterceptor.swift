import AppKit

/// Sends clicks on the mic part of the menu bar icon to `onMicClick` instead of letting
/// MenuBarExtra open its window. MenuBarExtra has no hit-testing API, so a local event
/// monitor sees mouse-downs on our own status item first and swallows the ones that land
/// on the mic. Everything else passes through untouched.
@MainActor
final class MicClickInterceptor {
    private weak var statusItem: NSStatusItem?
    private let isActive: () -> Bool
    private let onMicClick: () -> Void
    private var monitor: Any?

    init(statusItem: NSStatusItem, isActive: @escaping () -> Bool, onMicClick: @escaping () -> Void) {
        self.statusItem = statusItem
        self.isActive = isActive
        self.onMicClick = onMicClick
        monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            // Local monitors run on the main thread; NSEvent isn't Sendable, so only Sendable values cross.
            nonisolated(unsafe) let event = event
            let swallow = MainActor.assumeIsolated { self?.handle(event) ?? false }
            return swallow ? nil : event
        }
    }

    private func handle(_ event: NSEvent) -> Bool {
        guard isActive(), let button = statusItem?.button, event.window === button.window else { return false }
        let point = button.convert(event.locationInWindow, from: nil)
        let imageWidth = button.image?.size.width ?? 0
        let imageLeft = (button.bounds.width - imageWidth) / 2
        guard point.x < imageLeft + MenuBarIcon.micSegmentWidth else { return false }
        onMicClick()
        return true
    }
}
