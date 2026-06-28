import WidgetKit
import Foundation
import VisioCore

struct CallsProvider: TimelineProvider {
    func placeholder(in context: Context) -> CallsEntry {
        CallsEntry(date: .now, calls: [])
    }

    func getSnapshot(in context: Context, completion: @escaping (CallsEntry) -> Void) {
        completion(entry(at: .now, copied: false))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CallsEntry>) -> Void) {
        // Refresh hourly as a backstop; the app also reloads on calendar changes.
        let next = Calendar.current.date(byAdding: .hour, value: 1, to: .now) ?? .now

        // If a link was just copied, flash "Lien copié" now and revert when the window ends.
        let copiedAt = SharedStore.defaults.object(forKey: SharedStore.lastLinkCopiedKey) as? Date
        let window = SharedStore.copyFeedbackWindow
        if let copiedAt, Date.now.timeIntervalSince(copiedAt) < window {
            let revert = copiedAt.addingTimeInterval(window)
            let entries = [entry(at: .now, copied: true), entry(at: revert, copied: false)]
            completion(Timeline(entries: entries, policy: .after(next)))
            return
        }

        completion(Timeline(entries: [entry(at: .now, copied: false)], policy: .after(next)))
    }

    private func entry(at date: Date, copied: Bool) -> CallsEntry {
        let snapshot = WidgetSnapshot.load(from: SharedStore.defaults)
        let accent = Settings.load(from: SharedStore.defaults).imminentColor
        return CallsEntry(date: date, calls: snapshot?.meetings ?? [], accent: accent, copied: copied)
    }
}
