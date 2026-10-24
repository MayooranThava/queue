import Foundation

/// The next block the widget can start, or the head of the queue while a block is in focus.
public struct QueueWidgetNow: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var title: String
    public var duration: TimeInterval
    public var difficulty: TaskDifficulty

    public init(id: UUID, title: String, duration: TimeInterval, difficulty: TaskDifficulty) {
        self.id = id
        self.title = title
        self.duration = duration
        self.difficulty = difficulty
    }
}

/// A later block shown under Up next. Difficulty stays on `now` only.
public struct QueueWidgetUpcoming: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var title: String
    public var duration: TimeInterval

    public init(id: UUID, title: String, duration: TimeInterval) {
        self.id = id
        self.title = title
        self.duration = duration
    }
}

/// Idle-queue snapshot written to the App Group whenever the queue changes.
/// Remaining focus time stays on `FocusWidgetSnapshot`; this payload is the queue around it.
public struct QueueWidgetSnapshot: Codable, Sendable, Equatable {
    public var now: QueueWidgetNow?
    public var upNext: [QueueWidgetUpcoming]
    public var doneToday: Int
    public var plannedToday: Int
    public var minutesFocusedToday: Int
    public var updatedAt: Date

    public init(
        now: QueueWidgetNow?,
        upNext: [QueueWidgetUpcoming],
        doneToday: Int,
        plannedToday: Int,
        minutesFocusedToday: Int,
        updatedAt: Date
    ) {
        self.now = now
        self.upNext = upNext
        self.doneToday = doneToday
        self.plannedToday = plannedToday
        self.minutesFocusedToday = minutesFocusedToday
        self.updatedAt = updatedAt
    }

    public var isEmpty: Bool { now == nil }

    /// The block after the one in focus. Blank titles are treated as no next task.
    public var nextQueuedTitle: String? {
        guard let raw = upNext.first?.title else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

public enum QueueWidgetSnapshotBuilder {
    /// Medium shows 2–3 of these; Large can show the full list.
    public static let upNextLimit = 5

    public static func make(
        tasks: [QueueTask],
        at now: Date,
        calendar: Calendar = .current,
        upNextLimit: Int = QueueWidgetSnapshotBuilder.upNextLimit
    ) -> QueueWidgetSnapshot {
        let active = QueueOrdering.activeTasks(tasks)

        let head = active.first.map { task in
            QueueWidgetNow(
                id: task.id,
                title: task.title,
                duration: task.estimatedDuration,
                difficulty: task.difficulty
            )
        }
        let upcoming = active.dropFirst().prefix(max(0, upNextLimit)).map { task in
            QueueWidgetUpcoming(id: task.id, title: task.title, duration: task.estimatedDuration)
        }

        let done = tasks.filter { completedToday($0, at: now, calendar: calendar) }
        let minutes = done.reduce(0.0) { $0 + $1.actualFocusDuration }

        return QueueWidgetSnapshot(
            now: head,
            upNext: Array(upcoming),
            doneToday: done.count,
            plannedToday: done.count + active.count,
            minutesFocusedToday: Int((minutes / 60).rounded()),
            updatedAt: now
        )
    }

    private static func completedToday(_ task: QueueTask, at now: Date, calendar: Calendar) -> Bool {
        guard let completedAt = task.completedAt else { return false }
        return calendar.isDate(completedAt, inSameDayAs: now)
    }
}

/// App Group store for `QueueWidgetSnapshot`.
public enum QueueActivityStore {
    public static let snapshotKey = "queue.widget.snapshot.v1"

    public static func save(_ snapshot: QueueWidgetSnapshot, defaults: UserDefaults = AppGroupDefaults.shared) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: snapshotKey)
    }

    public static func load(defaults: UserDefaults = AppGroupDefaults.shared) -> QueueWidgetSnapshot? {
        guard let data = defaults.data(forKey: snapshotKey) else { return nil }
        return try? JSONDecoder().decode(QueueWidgetSnapshot.self, from: data)
    }

    public static func clear(defaults: UserDefaults = AppGroupDefaults.shared) {
        defaults.removeObject(forKey: snapshotKey)
    }
}

/// Bumped only by widget intents so the app can tell an external edit from its own writes.
public enum WidgetStoreGeneration {
    public static let key = "queue.widget.store.generation"

    public static func current(defaults: UserDefaults = AppGroupDefaults.shared) -> Int {
        defaults.integer(forKey: key)
    }

    @discardableResult
    public static func bump(defaults: UserDefaults = AppGroupDefaults.shared) -> Int {
        let next = defaults.integer(forKey: key) + 1
        defaults.set(next, forKey: key)
        return next
    }
}

public enum QueueWidgetFormatting {
    public static func minutesLabel(_ duration: TimeInterval) -> String {
        let minutes = max(1, Int((duration / 60).rounded()))
        return "\(minutes)m"
    }

    /// Spoken duration for VoiceOver. The visible chip stays compact (`15m`).
    public static func spokenMinutes(_ duration: TimeInterval) -> String {
        let minutes = max(1, Int((duration / 60).rounded()))
        let unit = minutes == 1 ? "minute" : "minutes"
        return "\(minutes) \(unit)"
    }

    public static func todayCount(done: Int, planned: Int) -> String {
        "\(done)/\(planned) today"
    }

    public static func todayAccessibility(done: Int, planned: Int) -> String {
        "\(done) of \(planned) done today"
    }

    public static func rowAccessibility(title: String, duration: TimeInterval) -> String {
        "\(title), \(spokenMinutes(duration))"
    }

    /// Lock Screen rectangular idle line from the brief: "Next: <title> · 15m".
    public static func lockScreenNextLine(title: String, duration: TimeInterval) -> String {
        "Next: \(title) · \(minutesLabel(duration))"
    }

    /// Spoken next-task label, without the Start action.
    public static func nextTaskSpoken(title: String, duration: TimeInterval) -> String {
        "Next task: \(title), \(spokenMinutes(duration))."
    }

    /// VoiceOver label for the idle Start affordance. Matches the brief's spoken form.
    public static func nextTaskAccessibility(title: String, duration: TimeInterval) -> String {
        "\(nextTaskSpoken(title: title, duration: duration)) Start."
    }

    public static func focusAccessibility(title: String, status: String, remaining: TimeInterval) -> String {
        "\(title), \(status). Time remaining \(FocusTimerFormatting.spoken(remaining))."
    }
}

public enum QueueWidgetChrome: Equatable, Sendable {
    case needsLaunch
    case empty
    case ready(QueueWidgetNow)
    case focusing
    case paused
    case expired
}

public enum QueueWidgetButton: Equatable, Sendable {
    case startNext
    case pause
    case resume
    case done
    case extendFive
}

public enum QueueWidgetChromeState {
    /// `at` is the timeline entry date. A running session with no time left is Time's up
    /// even if the process has not marked the session expired yet.
    public static func make(
        focus: FocusWidgetSnapshot?,
        queue: QueueWidgetSnapshot?,
        at now: Date
    ) -> QueueWidgetChrome {
        if let focus, focus.isActivelyTiming {
            let unfinished = focus.session.state == .expired || focus.remaining(at: now) <= 0
            if unfinished && focus.session.state != .paused {
                return .expired
            }
            switch focus.session.state {
            case .paused:
                return .paused
            case .expired:
                return .expired
            case .running, .idle, .completed:
                return .focusing
            }
        }
        guard let queue else { return .needsLaunch }
        guard let nowTask = queue.now else { return .empty }
        return .ready(nowTask)
    }

    public static func buttons(for chrome: QueueWidgetChrome) -> [QueueWidgetButton] {
        switch chrome {
        case .needsLaunch, .empty:
            return []
        case .ready:
            return [.startNext]
        case .focusing:
            return [.pause, .done, .extendFive]
        case .paused:
            return [.resume, .done, .extendFive]
        case .expired:
            return [.done, .extendFive]
        }
    }
}

/// "Done by 4:30 PM" for the Large family. Uses `QueueSchedule`, with the live
/// remaining time substituted for the block that is already running.
public enum QueueWidgetProjection {
    public static func projectedFinish(
        queue: QueueWidgetSnapshot,
        focus: FocusWidgetSnapshot?,
        at now: Date
    ) -> Date? {
        var tasks: [QueueTask] = []
        if let head = queue.now {
            var duration = head.duration
            if let focus, focus.isActivelyTiming, focus.taskID == head.id {
                duration = max(0, focus.remaining(at: now))
            }
            tasks.append(
                QueueTask(
                    id: head.id,
                    title: head.title,
                    estimatedDuration: duration,
                    difficulty: head.difficulty,
                    queuePosition: 0
                )
            )
        }
        for (index, item) in queue.upNext.enumerated() {
            tasks.append(
                QueueTask(
                    id: item.id,
                    title: item.title,
                    estimatedDuration: item.duration,
                    queuePosition: index + 1
                )
            )
        }
        guard let last = tasks.last else { return nil }
        let starts = QueueSchedule.projectedStarts(orderedActiveTasks: tasks, from: now)
        guard let start = starts[last.id] else { return nil }
        return start.addingTimeInterval(max(60, last.estimatedDuration))
    }
}

/// Decides when the app may copy the pre-App-Group SwiftData file, and when a
/// widget intent is allowed to open that file. Opening early would create an
/// empty store and hide the existing queue.
public enum AppGroupStoreMigration {
    public static func shouldCopyLegacyStore(
        legacyExists: Bool,
        destinationExists: Bool,
        markerExists: Bool
    ) -> Bool {
        legacyExists && !destinationExists && !markerExists
    }

    public static func widgetMayOpenStore(appGroupAvailable: Bool, markerExists: Bool) -> Bool {
        if !appGroupAvailable { return true }
        return markerExists
    }
}
