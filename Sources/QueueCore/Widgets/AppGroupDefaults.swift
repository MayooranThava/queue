import Foundation

/// Shared `UserDefaults` suite for the app, widget extension, and Live Activity.
public enum AppGroupDefaults {
    public static let suiteID = "group.com.queueapp.Queueup"

    public static var shared: UserDefaults {
        UserDefaults(suiteName: suiteID) ?? .standard
    }
}
