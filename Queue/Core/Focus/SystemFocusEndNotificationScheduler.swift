import Foundation
import UserNotifications
import QueueCore

protocol FocusNotificationAuthorizing: Sendable {
    func authorizationStatus() async -> FocusNotificationAuthorization
    func requestAuthorization() async -> FocusNotificationAuthorization
}

/// Silent stand-in so a repository without a notification center never presents a prompt.
struct SilentFocusNotificationAuthorizer: FocusNotificationAuthorizing {
    func authorizationStatus() async -> FocusNotificationAuthorization { .denied }
    func requestAuthorization() async -> FocusNotificationAuthorization { .denied }
}

/// Performs QueueCore focus-alert commands with a local notification.
/// Denial and center failures are ignored so the timer itself keeps running.
final class SystemFocusEndNotificationScheduler: NSObject, FocusEndNotificationScheduling, FocusNotificationAuthorizing, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = SystemFocusEndNotificationScheduler()

    private let lock = NSLock()
    private var onOpenTask: (@Sendable (UUID?) -> Void)?
    private let center: UNUserNotificationCenter

    override init() {
        center = .current()
        super.init()
    }

    func install() {
        center.delegate = self
    }

    func setOpenTaskHandler(_ handler: @escaping @Sendable (UUID?) -> Void) {
        lock.lock()
        onOpenTask = handler
        lock.unlock()
    }

    func authorizationStatus() async -> FocusNotificationAuthorization {
        switch await center.notificationSettings().authorizationStatus {
        case .notDetermined:
            return .notDetermined
        case .authorized, .provisional, .ephemeral:
            return .authorized
        case .denied:
            return .denied
        @unknown default:
            return .denied
        }
    }

    func requestAuthorization() async -> FocusNotificationAuthorization {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound])
            return granted ? .authorized : .denied
        } catch {
            return .denied
        }
    }

    func apply(_ command: FocusEndNotificationCommand) async {
        switch command {
        case .schedule(let alert):
            await schedule(alert)
        case .cancel(let andDelivered):
            center.removePendingNotificationRequests(withIdentifiers: [FocusEndAlert.requestIdentifier])
            if andDelivered {
                center.removeDeliveredNotifications(withIdentifiers: [FocusEndAlert.requestIdentifier])
            }
        case .leaveScheduledAlert:
            break
        }
    }

    private func schedule(_ alert: FocusEndAlert) async {
        let status = await authorizationStatus()
        guard FocusNotificationPermissionPolicy.canSchedule(status: status) else {
            if status == .denied {
                center.removePendingNotificationRequests(withIdentifiers: [FocusEndAlert.requestIdentifier])
            }
            return
        }

        let interval = alert.fireDate.timeIntervalSinceNow
        // Time-interval triggers must be strictly positive. Sub-second leftovers round up to 1s.
        guard interval > 0 else { return }
        let triggerInterval = max(interval, 1)

        let content = UNMutableNotificationContent()
        content.title = alert.notificationTitle
        content.body = alert.notificationBody
        content.sound = .default
        content.threadIdentifier = FocusEndAlert.requestIdentifier
        let link = QueueDeepLink.focus(taskID: alert.taskID)
        content.userInfo = [
            FocusEndAlert.taskIDUserInfoKey: alert.taskID.uuidString,
            FocusEndAlert.sessionIDUserInfoKey: alert.sessionID.uuidString,
            FocusEndAlert.deepLinkUserInfoKey: link.absoluteString
        ]

        let request = UNNotificationRequest(
            identifier: FocusEndAlert.requestIdentifier,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: triggerInterval, repeats: false)
        )
        // A new request with the same identifier replaces the pending one, including after +5 minutes.
        center.removeDeliveredNotifications(withIdentifiers: [FocusEndAlert.requestIdentifier])
        do {
            try await center.add(request)
        } catch {
            // Permission denial or a missing center must not fail the focus session.
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let info = response.notification.request.content.userInfo
        let taskID = taskID(from: info)
        lock.lock()
        let handler = onOpenTask
        lock.unlock()
        handler?(taskID)
        completionHandler()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    private func taskID(from userInfo: [AnyHashable: Any]) -> UUID? {
        if let raw = userInfo[FocusEndAlert.taskIDUserInfoKey] as? String,
           let taskID = UUID(uuidString: raw) {
            return taskID
        }
        if let raw = userInfo[FocusEndAlert.deepLinkUserInfoKey] as? String,
           let url = URL(string: raw) {
            return QueueDeepLink.taskID(from: url)
        }
        return nil
    }
}
