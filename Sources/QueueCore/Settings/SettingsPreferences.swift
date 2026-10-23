import Foundation

/// Companion motion stored in `UserPreferencesEntity.animationIntensityRaw`.
///
/// The column is a free string. These two raw values are the ones already written
/// by the model default (`standard`) and by migration fixtures (`reduced`).
public enum AnimationIntensity: String, Codable, Sendable, CaseIterable, Identifiable {
    case reduced
    case standard

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .reduced: return "Reduced"
        case .standard: return "Standard"
        }
    }

    public var summary: String {
        switch self {
        case .reduced: return "Holds the companion still."
        case .standard: return "Plays the usual companion motion."
        }
    }

    /// Reduced intensity uses a still pose, the same outcome as Reduce Motion.
    public var allowsMotion: Bool { self == .standard }

    /// Unknown stored strings display as Standard and are left unchanged until the user picks a value.
    public static func resolved(_ raw: String) -> AnimationIntensity {
        AnimationIntensity(rawValue: raw) ?? .standard
    }
}

public extension MotivationProfile {
    var displayName: String {
        switch self {
        case .balanced: return "Balanced"
        case .speedRunner: return "Speed Runner"
        case .consistencyBuilder: return "Consistency Builder"
        }
    }

    var summary: String {
        switch self {
        case .balanced: return "Completion plus modest on-time bonuses."
        case .speedRunner: return "More emphasis on finishing within estimates."
        case .consistencyBuilder: return "Streaks and daily rhythm over speed."
        }
    }
}

/// Inclusive range for the daily-goal stepper. The stored column stays an `Int`.
public enum DailyGoalCount {
    public static let minimum = 1
    public static let maximum = 10
    public static let range = minimum...maximum

    public static func clamped(_ value: Int) -> Int {
        min(max(value, minimum), maximum)
    }

    public static func label(for count: Int) -> String {
        count == 1 ? "1 task" : "\(count) tasks"
    }
}

/// `CFBundleShortVersionString` plus `CFBundleVersion`, read from a bundle.
public enum AppVersionFormatting {
    public static let shortVersionInfoKey = "CFBundleShortVersionString"
    public static let buildInfoKey = "CFBundleVersion"

    public static func display(shortVersion: String?, build: String?) -> String {
        let version = nonempty(shortVersion)
        let buildNumber = nonempty(build)
        switch (version, buildNumber) {
        case let (version?, buildNumber?):
            return "\(version) (\(buildNumber))"
        case let (version?, nil):
            return version
        case let (nil, buildNumber?):
            return buildNumber
        case (nil, nil):
            return "Unknown"
        }
    }

    public static func display(in bundle: Bundle) -> String {
        let short = bundle.object(forInfoDictionaryKey: shortVersionInfoKey) as? String
        let build = bundle.object(forInfoDictionaryKey: buildInfoKey) as? String
        return display(shortVersion: short, build: build)
    }

    private static func nonempty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}

/// Whether iOS will deliver Queue alerts. Provisional and ephemeral count as allowed
/// because the scheduler maps them to `FocusNotificationAuthorization.authorized`.
public enum NotificationSettingsStatus {
    public static func isAllowed(_ status: FocusNotificationAuthorization) -> Bool {
        FocusNotificationPermissionPolicy.canSchedule(status: status)
    }

    public static func label(for status: FocusNotificationAuthorization) -> String {
        isAllowed(status) ? "Allowed" : "Not allowed"
    }
}

public struct PlannedStartTimeAdoption: Equatable, Sendable {
    public var entityValue: Bool
    public var clearLegacy: Bool

    public init(entityValue: Bool, clearLegacy: Bool) {
        self.entityValue = entityValue
        self.clearLegacy = clearLegacy
    }
}

/// The Queue toolbar used to keep show-start-times in `UserDefaults`.
/// Adopt that flag into the preferences row once, then clear it so a later
/// Settings change is not overwritten on the next launch.
public enum PlannedStartTimePreference {
    public static func adopt(
        entityValue: Bool,
        legacyValue: Bool,
        entityExists: Bool
    ) -> PlannedStartTimeAdoption {
        guard entityExists, legacyValue else {
            return PlannedStartTimeAdoption(entityValue: entityValue, clearLegacy: false)
        }
        return PlannedStartTimeAdoption(entityValue: true, clearLegacy: true)
    }
}
