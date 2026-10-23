import Foundation

/// One widget button press, before it is turned into a repository call.
public enum WidgetFocusAction: Equatable, Sendable {
    case startNext
    case pauseOrResume
    case complete
    case extendFiveMinutes
}

/// The shared focus path a widget button must call. Widget code executes these
/// through `TaskRepository` so notifications, XP, and the timer stay in one place.
public enum WidgetFocusCommand: Equatable, Sendable {
    case startNext(taskID: UUID, plannedDuration: TimeInterval)
    case pause(taskID: UUID)
    case resume(taskID: UUID)
    case complete(taskID: UUID)
    case extend(taskID: UUID, by: TimeInterval)
}

public enum WidgetFocusRouting {
    /// Same five minutes as the in-app "+5 min" control.
    public static let fiveMinutes: TimeInterval = 5 * 60

    public static func command(
        for action: WidgetFocusAction,
        queue: QueueWidgetSnapshot?,
        focus: FocusWidgetSnapshot?
    ) -> WidgetFocusCommand? {
        switch action {
        case .startNext:
            guard focus?.isActivelyTiming != true, let now = queue?.now else { return nil }
            return .startNext(taskID: now.id, plannedDuration: now.duration)
        case .pauseOrResume:
            guard let focus, focus.isActivelyTiming else { return nil }
            switch focus.session.state {
            case .running:
                return .pause(taskID: focus.taskID)
            case .paused:
                return .resume(taskID: focus.taskID)
            case .expired, .idle, .completed:
                return nil
            }
        case .complete:
            guard let focus, focus.isActivelyTiming else { return nil }
            return .complete(taskID: focus.taskID)
        case .extendFiveMinutes:
            guard let focus, focus.isActivelyTiming else { return nil }
            return .extend(taskID: focus.taskID, by: fiveMinutes)
        }
    }
}

/// Narrow surface the widget uses to reach the app's focus methods.
public protocol WidgetFocusMutating {
    func startFocus(taskID: UUID, plannedDuration: TimeInterval) async throws
    func pauseFocus(taskID: UUID) async throws
    func resumeFocus(taskID: UUID) async throws
    func completeFocus(taskID: UUID) async throws
    func extendFocus(by duration: TimeInterval) async throws
}

public enum WidgetFocusIntentPerformer {
    public static func perform(
        _ command: WidgetFocusCommand,
        using focus: any WidgetFocusMutating
    ) async throws {
        switch command {
        case .startNext(let taskID, let plannedDuration):
            try await focus.startFocus(taskID: taskID, plannedDuration: plannedDuration)
        case .pause(let taskID):
            try await focus.pauseFocus(taskID: taskID)
        case .resume(let taskID):
            try await focus.resumeFocus(taskID: taskID)
        case .complete(let taskID):
            try await focus.completeFocus(taskID: taskID)
        case .extend(_, let duration):
            try await focus.extendFocus(by: duration)
        }
    }
}
