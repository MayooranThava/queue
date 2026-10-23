import Foundation

/// App Group flag so a Live Activity update can honor Show companion.
///
/// The widget extension cannot read the SwiftData preferences row while the
/// system is archiving the activity, so the app publishes the toggle here
/// before it starts or updates the activity.
public enum CompanionPreferenceStore {
    public static let key = "queue.companion.visible.v1"

    /// Missing key means the app has not published a choice yet. Companion stays on.
    public static func isVisible(defaults: UserDefaults = AppGroupDefaults.shared) -> Bool {
        guard defaults.object(forKey: key) != nil else { return true }
        return defaults.bool(forKey: key)
    }

    public static func setVisible(_ isVisible: Bool, defaults: UserDefaults = AppGroupDefaults.shared) {
        defaults.set(isVisible, forKey: key)
    }
}
