import Foundation

enum SharedStore {
    static let suiteName = "group.com.meidosem.visionext"
    static var defaults: UserDefaults { UserDefaults(suiteName: suiteName) ?? .standard }

    /// Timestamp of the last "Copier un lien" tap, used to flash the widget's feedback.
    static let lastLinkCopiedKey = "lastLinkCopiedAt"
    /// How long the widget shows "Lien copié" after a copy.
    static let copyFeedbackWindow: TimeInterval = 2
}
