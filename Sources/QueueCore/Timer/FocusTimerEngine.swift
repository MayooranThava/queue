import Foundation

public enum FocusTimerState: String, Codable, Sendable, Equatable, Hashable {
    case idle
    case running
    case paused
    case expired
    case completed
}

public struct FocusTimerExtension: Codable, Sendable, Equatable, Hashable, Identifiable {
    public let id: UUID
    public let duration: TimeInterval
    public let createdAt: Date

    public init(id: UUID = UUID(), duration: TimeInterval, createdAt: Date) {
        self.id = id
        self.duration = duration
        self.createdAt = createdAt
    }
}

/// Authoritative focus session. Remaining time is always derived from timestamps.
public struct FocusSession: Codable, Sendable, Equatable, Hashable, Identifiable {
    public let id: UUID
    public let taskID: UUID
    public var sessionStart: Date
    public var segmentStart: Date
    public var plannedDuration: TimeInterval
    public var accumulatedActive: TimeInterval
    public var accumulatedPaused: TimeInterval
    public var state: FocusTimerState
    public var extensions: [FocusTimerExtension]
    public var completedAt: Date?

    public init(
        id: UUID = UUID(),
        taskID: UUID,
        sessionStart: Date,
        segmentStart: Date,
        plannedDuration: TimeInterval,
        accumulatedActive: TimeInterval = 0,
        accumulatedPaused: TimeInterval = 0,
        state: FocusTimerState = .running,
        extensions: [FocusTimerExtension] = [],
        completedAt: Date? = nil
    ) {
        self.id = id
        self.taskID = taskID
        self.sessionStart = sessionStart
        self.segmentStart = segmentStart
        self.plannedDuration = plannedDuration
        self.accumulatedActive = accumulatedActive
        self.accumulatedPaused = accumulatedPaused
        self.state = state
        self.extensions = extensions
        self.completedAt = completedAt
    }

    public var totalPlanned: TimeInterval {
        plannedDuration + extensions.reduce(0) { $0 + $1.duration }
    }

    /// Derives remaining time at `now`. Never negative.
    public func remaining(at now: Date) -> TimeInterval {
        max(0, totalPlanned - elapsedActive(at: now))
    }

    public func elapsedActive(at now: Date) -> TimeInterval {
        var active = accumulatedActive
        if state == .running {
            active += max(0, now.timeIntervalSince(segmentStart))
        }
        return active
    }

    public func isExpired(at now: Date) -> Bool {
        state == .running && remaining(at: now) <= 0
    }
}

public enum FocusTimerError: Error, Equatable, Sendable {
    case sessionAlreadyActive
    case noActiveSession
    case invalidState
    case alreadyCompleted
}

/// Pure timer calculations + session lifecycle. Persist `FocusSession` externally.
public actor FocusTimerEngine {
    private var session: FocusSession?
    private let clock: any QueueClock

    public init(clock: any QueueClock = SystemQueueClock(), session: FocusSession? = nil) {
        self.clock = clock
        self.session = session
    }

    public func currentSession() -> FocusSession? { session }

    public func start(taskID: UUID, plannedDuration: TimeInterval) throws -> FocusSession {
        if let session, session.state == .running || session.state == .paused {
            throw FocusTimerError.sessionAlreadyActive
        }
        let now = clock.now()
        let created = FocusSession(
            taskID: taskID,
            sessionStart: now,
            segmentStart: now,
            plannedDuration: plannedDuration,
            state: .running
        )
        session = created
        return created
    }

    public func restore(_ restored: FocusSession) {
        session = restored
    }

    public func clear() {
        session = nil
    }

    public func pause() throws -> FocusSession {
        guard var current = session else { throw FocusTimerError.noActiveSession }
        guard current.state == .running else { throw FocusTimerError.invalidState }
        let now = clock.now()
        current.accumulatedActive += max(0, now.timeIntervalSince(current.segmentStart))
        current.segmentStart = now
        current.state = .paused
        session = current
        return current
    }

    public func resume() throws -> FocusSession {
        guard var current = session else { throw FocusTimerError.noActiveSession }
        guard current.state == .paused else { throw FocusTimerError.invalidState }
        let now = clock.now()
        current.accumulatedPaused += max(0, now.timeIntervalSince(current.segmentStart))
        current.segmentStart = now
        current.state = .running
        session = current
        return current
    }

    public func extend(by duration: TimeInterval) throws -> FocusSession {
        guard var current = session else { throw FocusTimerError.noActiveSession }
        guard current.state == .running || current.state == .paused || current.state == .expired else {
            throw FocusTimerError.invalidState
        }
        let now = clock.now()
        current.extensions.append(FocusTimerExtension(duration: duration, createdAt: now))
        if current.state == .expired {
            current.segmentStart = now
            current.state = .running
        }
        session = current
        return current
    }

    /// Marks expired if remaining hit zero. Idempotent.
    public func evaluateExpiry() -> FocusSession? {
        guard var current = session, current.state == .running else { return session }
        let now = clock.now()
        if current.isExpired(at: now) {
            current.accumulatedActive = current.totalPlanned
            current.state = .expired
            current.segmentStart = now
            session = current
        }
        return session
    }

    public func complete() throws -> FocusSession {
        guard var current = session else { throw FocusTimerError.noActiveSession }
        guard current.state != .completed else { throw FocusTimerError.alreadyCompleted }
        let now = clock.now()
        if current.state == .running {
            current.accumulatedActive += max(0, now.timeIntervalSince(current.segmentStart))
        }
        current.state = .completed
        current.completedAt = now
        session = current
        return current
    }

    public func remaining() -> TimeInterval {
        guard let session else { return 0 }
        return session.remaining(at: clock.now())
    }

    /// Wall-clock jump policy: remaining is clamped to ≥ 0; completion must be explicit
    /// via `complete()` or expiry evaluation — never inferred twice.
    public func snapshotted(at now: Date? = nil) -> FocusSession? {
        guard var current = session else { return nil }
        let moment = now ?? clock.now()
        if current.state == .running, current.isExpired(at: moment) {
            current.accumulatedActive = current.totalPlanned
            current.state = .expired
            current.segmentStart = moment
            session = current
        }
        return session
    }
}
