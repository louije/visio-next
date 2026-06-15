import Foundation

/// Storage location shared with the future widget. Until the App Group entitlement
/// is added in Phase 2, `UserDefaults(suiteName:)` still returns a working,
/// app-local suite, so Phase 1 functions unchanged.
enum AppGroup {
    static let suiteName = "group.com.meidosem.visionext"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: suiteName) ?? .standard
    }
}
