import Foundation

/// Abstract clock for testable timing. Wall time is used for persistence;
/// tests inject a controllable implementation.
public protocol QueueClock: Sendable {
    func now() -> Date
}

public struct SystemQueueClock: QueueClock {
    public init() {}

    public func now() -> Date {
        Date()
    }
}

/// Thread-safe controllable clock for deterministic tests.
public final class ControllableClock: QueueClock, @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    public init(start: Date = Date(timeIntervalSince1970: 1_700_000_000)) {
        self.current = start
    }

    public func now() -> Date {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    public func advance(by interval: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        current = current.addingTimeInterval(interval)
    }

    public func set(_ date: Date) {
        lock.lock()
        defer { lock.unlock() }
        current = date
    }
}
