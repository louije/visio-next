import Foundation
import VisioCore

/// Storage location shared with the widget via the App Group entitlement
/// (`BridgeEndpoint.appGroupID`, configured in project.yml on both targets).
enum AppGroup {
    static var defaults: UserDefaults {
        UserDefaults(suiteName: BridgeEndpoint.appGroupID) ?? .standard
    }
}
