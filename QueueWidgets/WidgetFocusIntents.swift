import AppIntents
import SwiftData
import QueueCore

struct StartNextTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "Start next block"
    static var description = IntentDescription("Starts the next block in your queue.")
    static var openAppWhenRun = false
    static var isDiscoverable: Bool { false }

    func perform() async throws -> some IntentResult {
        await WidgetIntentRunner.run(.startNext)
        return .result()
    }
}

struct PauseResumeFocusIntent: AppIntent {
    static var title: LocalizedStringResource = "Pause or resume focus"
    static var description = IntentDescription("Pauses a running focus block, or resumes a paused one.")
    static var openAppWhenRun = false
    static var isDiscoverable: Bool { false }

    func perform() async throws -> some IntentResult {
        await WidgetIntentRunner.run(.pauseOrResume)
        return .result()
    }
}

struct CompleteTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "Mark block done"
    static var description = IntentDescription("Completes the current focus block and awards XP once.")
    static var openAppWhenRun = false
    static var isDiscoverable: Bool { false }

    func perform() async throws -> some IntentResult {
        await WidgetIntentRunner.run(.complete)
        return .result()
    }
}

struct ExtendFocusIntent: AppIntent {
    static var title: LocalizedStringResource = "Add five minutes"
    static var description = IntentDescription("Extends the current focus block by five minutes.")
    static var openAppWhenRun = false
    static var isDiscoverable: Bool { false }

    func perform() async throws -> some IntentResult {
        await WidgetIntentRunner.run(.extendFiveMinutes)
        return .result()
    }
}

/// Runs a widget button through the same `TaskRepository` methods the app uses,
/// so focus-end alerts are scheduled, rescheduled, or cancelled with the session.
@MainActor
enum WidgetIntentRunner {
    static func run(_ action: WidgetFocusAction) async {
        let queue = QueueActivityStore.load()
        let focus = FocusActivityStore.load()
        guard let command = WidgetFocusRouting.command(for: action, queue: queue, focus: focus) else {
            return
        }
        guard AppGroupStoreLocation.widgetMayOpenStore() else { return }

        let container = AppModelContainer.make(migrateLegacyStore: false)
        let context = ModelContext(container)
        let scheduler = SystemFocusEndNotificationScheduler.shared
        let repository = TaskRepository(
            context: context,
            focusNotifications: scheduler,
            notificationAuthorizer: scheduler
        )
        do {
            try await repository.bootstrapFromStore()
            try await WidgetFocusIntentPerformer.perform(
                command,
                using: RepositoryFocusMutator(repository: repository)
            )
            WidgetStoreGeneration.bump()
            WidgetStoreChangeCenter.post()
            let snapshot = await repository.currentFocusSnapshot()
            await FocusLiveActivityController.shared.sync(snapshot: snapshot)
        } catch {
            QueueWidgetReload.reload()
            return
        }
        QueueWidgetReload.reload()
    }
}

struct RepositoryFocusMutator: WidgetFocusMutating {
    let repository: TaskRepository

    func startFocus(taskID: UUID, plannedDuration: TimeInterval) async throws {
        _ = try await repository.beginFocus(taskID: taskID, plannedDuration: plannedDuration)
    }

    func pauseFocus(taskID: UUID) async throws {
        _ = try await repository.pauseFocus(taskID: taskID)
    }

    func resumeFocus(taskID: UUID) async throws {
        _ = try await repository.resumeFocus(taskID: taskID)
    }

    func completeFocus(taskID: UUID) async throws {
        _ = try await repository.completeFocus(taskID: taskID)
    }

    func extendFocus(by duration: TimeInterval) async throws {
        _ = try await repository.extendFocus(by: duration)
    }
}
