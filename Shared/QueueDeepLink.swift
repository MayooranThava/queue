import Foundation
import QueueCore

/// Shared deep links so Home Screen widgets, Live Activities, and focus-end alerts open straight into focus.
enum QueueDeepLink {
    static let scheme = FocusEndDeepLink.scheme
    static let focusHost = FocusEndDeepLink.focusHost
    static let queueHost = "queue"

    static var focus: URL {
        URL(string: "\(scheme)://\(focusHost)")!
    }

    static func focus(taskID: UUID) -> URL {
        FocusEndDeepLink.url(taskID: taskID)
    }

    static var queue: URL {
        URL(string: "\(scheme)://\(queueHost)")!
    }

    static func matchesFocus(_ url: URL) -> Bool {
        FocusEndDeepLink.isFocus(url)
    }

    static func matchesQueue(_ url: URL) -> Bool {
        url.scheme == scheme && (url.host == queueHost || url.path == "/\(queueHost)")
    }

    static func taskID(from url: URL) -> UUID? {
        FocusEndDeepLink.taskID(from: url)
    }
}
