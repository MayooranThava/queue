import Foundation

/// Shared deep links so Home Screen widgets / Live Activities open straight into focus.
enum QueueDeepLink {
    static let scheme = "queueapp"
    static let focusHost = "focus"
    static let queueHost = "queue"

    static var focus: URL {
        URL(string: "\(scheme)://\(focusHost)")!
    }

    static var queue: URL {
        URL(string: "\(scheme)://\(queueHost)")!
    }

    static func matchesFocus(_ url: URL) -> Bool {
        url.scheme == scheme && (url.host == focusHost || url.path == "/\(focusHost)")
    }

    static func matchesQueue(_ url: URL) -> Bool {
        url.scheme == scheme && (url.host == queueHost || url.path == "/\(queueHost)")
    }
}
