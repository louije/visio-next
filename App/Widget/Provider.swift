import WidgetKit
import Foundation
import VisioCore

struct CallsProvider: TimelineProvider {
    func placeholder(in context: Context) -> CallsEntry {
        CallsEntry(date: .now, calls: [])
    }

    func getSnapshot(in context: Context, completion: @escaping (CallsEntry) -> Void) {
        completion(entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CallsEntry>) -> Void) {
        // Refresh hourly as a backstop; the app also reloads on calendar changes.
        let next = Calendar.current.date(byAdding: .hour, value: 1, to: .now) ?? .now
        completion(Timeline(entries: [entry()], policy: .after(next)))
    }

    private func entry() -> CallsEntry {
        let snapshot = WidgetSnapshot.load(from: SharedStore.defaults)
        let accent = Settings.load(from: SharedStore.defaults).imminentColor
        return CallsEntry(date: .now, calls: snapshot?.meetings ?? [], accent: accent)
    }
}
