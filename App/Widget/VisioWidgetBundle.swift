import WidgetKit
import SwiftUI

@main
struct VisioWidgetBundle: WidgetBundle {
    var body: some Widget {
        NextCallWidget()
        CombinedWidget()
    }
}

struct NextCallWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "VisioNextCall", provider: CallsProvider()) { entry in
            NextCallView(entry: entry).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Prochain appel")
        .description("Affiche le prochain appel visio.")
        .supportedFamilies([.systemSmall])
    }
}

struct CombinedWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "VisioCombined", provider: CallsProvider()) { entry in
            CombinedView(entry: entry).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Appels & nouveau lien")
        .description("Prochain appel et création de lien.")
        .supportedFamilies([.systemMedium])
    }
}
