import Foundation

/// One local alert for the moment a running focus block ends.
/// The app keeps a single pending request, so a later schedule replaces the previous one.
public struct FocusEndAlert: Equatable, Sendable, Hashable {
    public static let requestIdentifier = "queue.focus-end"
    public static let taskIDUserInfoKey = "taskID"
    public static let sessionIDUserInfoKey = "sessionID"
    public static let deepLinkUserInfoKey = "deepLink"

    public let taskID: UUID
    public let sessionID: UUID
    public let taskTitle: String
    public let fireDate: Date

    public init(taskID: UUID, sessionID: UUID, taskTitle: String, fireDate: Date) {
        self.taskID = taskID
        self.sessionID = sessionID
        self.taskTitle = taskTitle
        self.fireDate = fireDate
    }

    /// Lock-screen title. The task name is the first thing the user reads.
    public var notificationTitle: String {
        let trimmed = taskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Focus block" : trimmed
    }

    public var notificationBody: String {
        "Time’s up — finish when you’re ready."
    }
}

public enum FocusEndNotificationCommand: Equatable, Sendable {
    /// Replace the pending alert. A +5 minute extension is a new fire date, not a second alert.
    case schedule(FocusEndAlert)
    /// Drop the pending alert so it cannot fire. `andDelivered` also clears a banner that already arrived.
    case cancel(andDelivered: Bool)
    /// The block has reached its end. Leave the scheduled alert alone so it can still arrive.
    case leaveScheduledAlert
}

/// Decides whether the pending focus-end alert should be scheduled, cancelled, or left to fire.
public enum FocusEndAlertPlanner {
    public static func command(
        session: FocusSession?,
        taskTitle: String,
        now: Date
    ) -> FocusEndNotificationCommand {
        guard let session else {
            return .cancel(andDelivered: true)
        }

        switch session.state {
        case .running:
            let remaining = session.remaining(at: now)
            guard remaining > 0 else {
                return .leaveScheduledAlert
            }
            return .schedule(
                FocusEndAlert(
                    taskID: session.taskID,
                    sessionID: session.id,
                    taskTitle: taskTitle,
                    fireDate: now.addingTimeInterval(remaining)
                )
            )
        case .paused:
            return .cancel(andDelivered: false)
        case .expired:
            return .leaveScheduledAlert
        case .completed, .idle:
            return .cancel(andDelivered: true)
        }
    }
}

/// App-side boundary for delivering focus-end alerts. QueueCore never imports UserNotifications.
public protocol FocusEndNotificationScheduling: Sendable {
    func apply(_ command: FocusEndNotificationCommand) async
}

public struct NoOpFocusEndNotificationScheduler: FocusEndNotificationScheduling {
    public init() {}

    public func apply(_ command: FocusEndNotificationCommand) async {}
}

/// Records commands so timer tests can prove schedule, replace, and cancel without a system center.
public actor RecordingFocusEndNotificationScheduler: FocusEndNotificationScheduling {
    public private(set) var applied: [FocusEndNotificationCommand] = []

    public init() {}

    public func apply(_ command: FocusEndNotificationCommand) async {
        applied.append(command)
    }
}

public struct FocusEndNotificationSync: Sendable {
    private let scheduler: any FocusEndNotificationScheduling

    public init(scheduler: any FocusEndNotificationScheduling) {
        self.scheduler = scheduler
    }

    public func sync(session: FocusSession?, taskTitle: String, now: Date) async {
        let command = FocusEndAlertPlanner.command(session: session, taskTitle: taskTitle, now: now)
        await scheduler.apply(command)
    }
}

public enum FocusNotificationAuthorization: Equatable, Sendable {
    case notDetermined
    case authorized
    case denied
}

public enum FocusNotificationPromptReason: Equatable, Sendable {
    /// Opening the app must not raise the system prompt.
    case coldLaunch
    /// Restoring a persisted timer must not raise the system prompt.
    case sessionRestore
    /// The notifications step in onboarding, after the user asks to allow alerts.
    case onboardingOptIn
    /// The first start, resume, or extension that needs an alert.
    case focusStartOrResume
}

public enum FocusNotificationPermissionPolicy {
    /// Ask only from an explicit onboarding action or when a focus timer is actually starting.
    public static func shouldRequest(
        status: FocusNotificationAuthorization,
        reason: FocusNotificationPromptReason
    ) -> Bool {
        guard status == .notDetermined else { return false }
        switch reason {
        case .coldLaunch, .sessionRestore:
            return false
        case .onboardingOptIn, .focusStartOrResume:
            return true
        }
    }

    public static func canSchedule(status: FocusNotificationAuthorization) -> Bool {
        status == .authorized
    }
}

/// `queueapp://focus?task=<uuid>` so a tapped alert opens that block.
public enum FocusEndDeepLink {
    public static let scheme = "queueapp"
    public static let focusHost = "focus"
    public static let taskQueryName = "task"

    public static func url(taskID: UUID) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = focusHost
        components.queryItems = [URLQueryItem(name: taskQueryName, value: taskID.uuidString)]
        return components.url ?? URL(string: "\(scheme)://\(focusHost)")!
    }

    public static func isFocus(_ url: URL) -> Bool {
        guard url.scheme == scheme else { return false }
        if url.host == focusHost { return true }
        return url.path == "/\(focusHost)"
    }

    public static func taskID(from url: URL) -> UUID? {
        guard isFocus(url) else { return nil }
        guard let raw = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == taskQueryName })?
            .value
        else { return nil }
        return UUID(uuidString: raw)
    }
}
