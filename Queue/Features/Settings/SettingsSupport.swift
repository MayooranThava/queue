import SwiftUI
import SwiftData
import UIKit
import QueueCore

enum UserPreferencesStore {
    /// The single preferences row, creating the default row when the store has none.
    static func entity(in context: ModelContext) -> UserPreferencesEntity {
        let descriptor = FetchDescriptor<UserPreferencesEntity>()
        if let existing = try? context.fetch(descriptor).first {
            return existing
        }
        let created = UserPreferencesEntity()
        context.insert(created)
        try? context.save()
        return created
    }
}

/// Fields Settings writes on `UserPreferencesEntity`.
///
/// `hasCompletedOnboarding` is launch state, not a preference.
enum UserPreferencesSettingsEditor {
    static func setCompanionVisible(_ value: Bool, on entity: UserPreferencesEntity) {
        entity.companionVisible = value
    }

    static func setAutoStartNextTask(_ value: Bool, on entity: UserPreferencesEntity) {
        entity.autoStartNextTask = value
    }

    static func setAnimationIntensity(_ value: AnimationIntensity, on entity: UserPreferencesEntity) {
        entity.animationIntensityRaw = value.rawValue
    }

    static func setMotivationProfile(_ value: MotivationProfile, on entity: UserPreferencesEntity) {
        entity.motivationProfileRaw = value.rawValue
    }

    static func setDailyGoalCount(_ value: Int, on entity: UserPreferencesEntity) {
        entity.dailyGoalCount = DailyGoalCount.clamped(value)
    }

    static func setShowPlannedStartTimes(_ value: Bool, on entity: UserPreferencesEntity) {
        entity.showPlannedStartTimes = value
    }
}

private struct QueueCompanionVisibleKey: EnvironmentKey {
    static let defaultValue = true
}

private struct QueueAnimationIntensityKey: EnvironmentKey {
    static let defaultValue = AnimationIntensity.standard
}

extension EnvironmentValues {
    var queueCompanionVisible: Bool {
        get { self[QueueCompanionVisibleKey.self] }
        set { self[QueueCompanionVisibleKey.self] = newValue }
    }

    var queueAnimationIntensity: AnimationIntensity {
        get { self[QueueAnimationIntensityKey.self] }
        set { self[QueueAnimationIntensityKey.self] = newValue }
    }
}

/// The selected theme, shared with widgets and Live Activity through the App Group.
@MainActor
final class QueueThemeSelection: ObservableObject {
    @Published private(set) var theme: QueueTheme

    init() {
        theme = QueueThemeStore.current()
    }

    func select(_ theme: QueueTheme) {
        guard theme != self.theme else { return }
        QueueThemeStore.save(theme)
        self.theme = theme
        QueueWidgetReload.reload()
        let snapshot = FocusActivityStore.load()
        Task { await FocusLiveActivityController.shared.sync(snapshot: snapshot) }
    }
}

/// Opens this app's page in iOS Settings.
@MainActor
enum AppSettingsLink {
    static var url: URL? {
        URL(string: UIApplication.openSettingsURLString)
    }

    static func open() {
        guard let url else { return }
        UIApplication.shared.open(url)
    }
}
