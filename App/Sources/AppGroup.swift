import Foundation

/// Storage location shared with the widget via the App Group entitlement
/// (`group.com.meidosem.visionext`, configured in project.yml on both targets).
enum AppGroup {
    static let suiteName = "group.com.meidosem.visionext"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: suiteName) ?? .standard
    }
}
