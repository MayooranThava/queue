import Foundation

/// App Group–backed store so the main app, widgets, and Live Activities share one timer snapshot.
public enum FocusActivityStore {
    public static let appGroupID = "group.com.queueapp.Queueup"
    public static let snapshotKey = "focus.widget.snapshot.v1"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    public static func save(_ snapshot: FocusWidgetSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: snapshotKey)
    }

    public static func load() -> FocusWidgetSnapshot? {
        guard let data = defaults.data(forKey: snapshotKey) else { return nil }
        return try? JSONDecoder().decode(FocusWidgetSnapshot.self, from: data)
    }

    public static func clear() {
        defaults.removeObject(forKey: snapshotKey)
    }
}
