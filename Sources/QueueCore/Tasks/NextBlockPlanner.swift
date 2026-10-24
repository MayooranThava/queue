import Foundation

/// The queued block offered after a celebration, plus the optional break and auto-start window.
public struct NextBlockOffer: Equatable, Sendable {
    public var task: QueueTask
    /// Optional break before that block. Skipping it starts the block early.
    public var breakDuration: TimeInterval
    /// `nil` when automatic start is off. Otherwise the visible countdown the person can cancel.
    public var autoStartCountdown: TimeInterval?

    public init(task: QueueTask, breakDuration: TimeInterval, autoStartCountdown: TimeInterval?) {
        self.task = task
        self.breakDuration = breakDuration
        self.autoStartCountdown = autoStartCountdown
    }

    public var willAutoStart: Bool { autoStartCountdown != nil }
}

/// Picks the next queued block and whether the celebration should start it on its own.
public enum NextBlockPlanner {
    public static let breakDuration: TimeInterval = 5 * 60
    /// Long enough to see the celebration and cancel. Short enough to still feel connected.
    public static let autoStartCountdown: TimeInterval = 5

    /// First still-queued task in FIFO order, excluding the block that just finished.
    /// Completed, skipped, review, archived, and in-focus tasks are not "next".
    public static func nextTask(after completedTaskID: UUID, in tasks: [QueueTask]) -> QueueTask? {
        tasks
            .filter { $0.id != completedTaskID && $0.status == .queued }
            .sorted(by: QueueOrdering.comesBefore)
            .first
    }

    /// `nil` when nothing is queued. The celebration then finishes the way it already does.
    public static func offer(
        after completedTaskID: UUID,
        in tasks: [QueueTask],
        autoStartNextTask: Bool
    ) -> NextBlockOffer? {
        guard let task = nextTask(after: completedTaskID, in: tasks) else { return nil }
        return NextBlockOffer(
            task: task,
            breakDuration: breakDuration,
            autoStartCountdown: autoStartNextTask ? autoStartCountdown : nil
        )
    }
}

/// Calm labels for the celebration and the break. No streak pressure.
public enum NextBlockCopy {
    public static let breakButtonTitle = "Take a 5-min break first"
    public static let skipBreakTitle = "Skip break"
    public static let leaveBreakTitle = "Done for now"
    public static let cancelAutoStartTitle = "Not now"
    public static let breakHeading = "Break"

    public static func startButtonTitle(taskTitle: String) -> String {
        "Start next: \(taskTitle)"
    }

    public static func breakNextLine(taskTitle: String) -> String {
        "Next up: \(taskTitle)"
    }

    public static func autoStartStatus(taskTitle: String, secondsRemaining: Int) -> String {
        let seconds = max(0, secondsRemaining)
        if seconds == 0 {
            return "Starting \(taskTitle)"
        }
        if seconds == 1 {
            return "Starting \(taskTitle) in 1 second"
        }
        return "Starting \(taskTitle) in \(seconds) seconds"
    }

    /// Whole seconds still showing. Never negative.
    public static func displayedSeconds(remaining: TimeInterval) -> Int {
        max(0, Int(remaining.rounded(.up)))
    }
}

/// Remaining time derived from a start instant. A backwards clock does not stretch the countdown.
public enum CountdownClock {
    public static func remaining(startedAt: Date, duration: TimeInterval, now: Date) -> TimeInterval {
        let elapsed = now.timeIntervalSince(startedAt)
        if elapsed < 0 { return max(0, duration) }
        return max(0, duration - elapsed)
    }

    public static func isComplete(startedAt: Date, duration: TimeInterval, now: Date) -> Bool {
        now.timeIntervalSince(startedAt) >= duration
    }

    /// Suspends until the countdown elapses. Returns false when the task is cancelled.
    public static func waitUntilComplete(startedAt: Date, duration: TimeInterval) async -> Bool {
        while !Task.isCancelled {
            let now = Date()
            if isComplete(startedAt: startedAt, duration: duration, now: now) {
                return true
            }
            let slice = min(max(remaining(startedAt: startedAt, duration: duration, now: now), 0.05), 0.5)
            do {
                try await Task.sleep(nanoseconds: UInt64((slice * 1_000_000_000).rounded()))
            } catch {
                return false
            }
        }
        return false
    }
}

public enum NextBlockHandoff: Equatable, Sendable {
    /// Begin focus on the next block.
    case startNext
    /// The countdown is still running.
    case wait
    /// Stay here. Do not start another block.
    case stay
}

public enum BreakExit: Equatable, Sendable {
    /// Leave the break early and start the next block.
    case skip
    /// The break countdown reached zero.
    case finished
    /// Leave without starting. The finished block stays finished.
    case leave
}

/// Decides whether a break or an automatic start should begin the next block.
public enum NextBlockHandoffResolver {
    public static func autoStart(
        cancelled: Bool,
        startedAt: Date,
        duration: TimeInterval,
        now: Date
    ) -> NextBlockHandoff {
        if cancelled { return .stay }
        if CountdownClock.isComplete(startedAt: startedAt, duration: duration, now: now) {
            return .startNext
        }
        return .wait
    }

    public static func resolveBreak(_ exit: BreakExit) -> NextBlockHandoff {
        switch exit {
        case .skip, .finished:
            return .startNext
        case .leave:
            return .stay
        }
    }

    public static func afterBreak(
        skipped: Bool,
        startedAt: Date,
        duration: TimeInterval,
        now: Date
    ) -> NextBlockHandoff {
        if skipped {
            return resolveBreak(.skip)
        }
        if CountdownClock.isComplete(startedAt: startedAt, duration: duration, now: now) {
            return resolveBreak(.finished)
        }
        return .wait
    }
}
