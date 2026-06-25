import Foundation

enum SharedStore {
    static let suiteName = "group.com.meidosem.visionext"
    static var defaults: UserDefaults { UserDefaults(suiteName: suiteName) ?? .standard }
}
