import Foundation
import Testing
@testable import QueueCore

@Suite("Queue widget snapshot")
struct QueueWidgetSnapshotTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("Empty queue has no next block and a zero today count")
    func emptyQueue() {
        let snapshot = QueueWidgetSnapshotBuilder.make(tasks: [], at: now, calendar: calendar)
        #expect(snapshot.now == nil)
        #expect(snapshot.upNext.isEmpty)
        #expect(snapshot.doneToday == 0)
        #expect(snapshot.plannedToday == 0)
        #expect(snapshot.minutesFocusedToday == 0)
        #expect(QueueWidgetChromeState.make(focus: nil, queue: snapshot, at: now) == .empty)
    }

    @Test("Idle snapshot shows the next block, the following blocks, and today's done count")
    func readyQueue() {
        let done = task(
            title: "Shipped yesterday's notes",
            position: 0,
            status: .completed,
            completedAt: now.addingTimeInterval(-30 * 60),
            focus: 20 * 60
        )
        let yesterday = task(
            title: "Old block",
            position: 1,
            status: .completed,
            completedAt: now.addingTimeInterval(-26 * 60 * 60),
            focus: 15 * 60
        )
        let head = task(title: "Update résumé", position: 2, duration: 15 * 60, difficulty: .easy)
        let second = task(title: "Reply to Alex", position: 3, duration: 20 * 60)
        let third = task(title: "Sketch the widget", position: 4, duration: 15 * 60)
        let fourth = task(title: "Stretch", position: 5, duration: 15 * 60)
        let skipped = task(title: "Skipped", position: 6, status: .skipped)

        let snapshot = QueueWidgetSnapshotBuilder.make(
            tasks: [fourth, head, skipped, done, third, yesterday, second],
            at: now,
            calendar: calendar
        )

        #expect(snapshot.now?.id == head.id)
        #expect(snapshot.now?.title == "Update résumé")
        #expect(snapshot.now?.duration == 15 * 60 as TimeInterval)
        #expect(snapshot.now?.difficulty == .easy)
        #expect(snapshot.upNext.map(\.id) == [second.id, third.id, fourth.id])
        #expect(snapshot.upNext.map(\.title) == ["Reply to Alex", "Sketch the widget", "Stretch"])
        #expect(snapshot.doneToday == 1)
        #expect(snapshot.plannedToday == 5)
        #expect(snapshot.minutesFocusedToday == 20)
        #expect(snapshot.updatedAt == now)

        let chrome = QueueWidgetChromeState.make(focus: nil, queue: snapshot, at: now)
        #expect(chrome == .ready(snapshot.now!))
        #expect(QueueWidgetChromeState.buttons(for: chrome) == [.startNext])
        let label = QueueWidgetFormatting.nextTaskAccessibility(title: head.title, duration: head.estimatedDuration)
        #expect(label == "Next task: Update résumé, 15 minutes. Start.")
        #expect(!label.contains("No active focus"))
        #expect(QueueWidgetFormatting.todayCount(done: snapshot.doneToday, planned: snapshot.plannedToday) == "1/5 today")
        #expect(QueueWidgetFormatting.minutesLabel(head.estimatedDuration) == "15m")
        #expect(QueueWidgetFormatting.spokenMinutes(head.estimatedDuration) == "15 minutes")
        #expect(QueueWidgetFormatting.spokenMinutes(60 as TimeInterval) == "1 minute")
        #expect(QueueWidgetFormatting.lockScreenNextLine(title: head.title, duration: head.estimatedDuration) == "Next: Update résumé · 15m")
        #expect(QueueWidgetFormatting.nextTaskSpoken(title: head.title, duration: head.estimatedDuration) == "Next task: Update résumé, 15 minutes.")
        #expect(QueueWidgetFormatting.rowAccessibility(title: "Reply to Alex", duration: 20 * 60 as TimeInterval) == "Reply to Alex, 20 minutes")
        #expect(QueueWidgetFormatting.todayAccessibility(done: 1, planned: 5) == "1 of 5 done today")
    }

    @Test("Gallery focus placeholder uses the 15-minute preset")
    func galleryPlaceholderIsFifteenMinutes() {
        let snapshot = FocusWidgetSnapshot.galleryPlaceholder(at: now)
        #expect(snapshot.estimatedDuration == QueueTask.defaultEstimatedDuration)
        #expect(snapshot.session.plannedDuration == 15 * 60)
        #expect(snapshot.session.state == .running)
        #expect(snapshot.isActivelyTiming)
    }

    @Test("Up next keeps at most five blocks after the head")
    func upNextIsCapped() {
        let tasks = (0..<8).map { index in
            task(title: "Block \(index)", position: index, duration: 15 * 60)
        }
        let snapshot = QueueWidgetSnapshotBuilder.make(tasks: tasks, at: now, calendar: calendar)
        #expect(snapshot.now?.title == "Block 0")
        #expect(snapshot.upNext.map(\.title) == ["Block 1", "Block 2", "Block 3", "Block 4", "Block 5"])
    }

    @Test("A missing snapshot is not treated as an empty queue")
    func missingSnapshotNeedsLaunch() {
        #expect(QueueWidgetChromeState.make(focus: nil, queue: nil, at: now) == .needsLaunch)
        #expect(QueueWidgetChromeState.buttons(for: .needsLaunch).isEmpty)
    }

    @Test("Focus, pause, and time's up choose the matching buttons")
    func chromeButtonsFollowSession() {
        let head = task(title: "Write", position: 0)
        let queue = QueueWidgetSnapshotBuilder.make(tasks: [head], at: now, calendar: calendar)
        let running = focusSnapshot(taskID: head.id, state: .running)
        let paused = focusSnapshot(taskID: head.id, state: .paused)
        let expired = focusSnapshot(taskID: head.id, state: .expired)

        #expect(QueueWidgetChromeState.make(focus: running, queue: queue, at: now) == .focusing)
        #expect(QueueWidgetChromeState.buttons(for: .focusing) == [.pause, .done, .extendFive])
        #expect(QueueWidgetChromeState.make(focus: paused, queue: queue, at: now) == .paused)
        #expect(QueueWidgetChromeState.buttons(for: .paused) == [.resume, .done, .extendFive])
        #expect(QueueWidgetChromeState.make(focus: expired, queue: queue, at: now) == .expired)
        #expect(QueueWidgetChromeState.buttons(for: .expired) == [.done, .extendFive])

        let elapsed = focusSnapshot(taskID: head.id, state: .running, planned: 15 * 60, elapsed: 15 * 60)
        #expect(QueueWidgetChromeState.make(focus: elapsed, queue: queue, at: now) == .expired)
        #expect(QueueWidgetChromeState.make(focus: paused, queue: queue, at: now.addingTimeInterval(3600)) == .paused)
    }

    @Test("Projected finish follows QueueSchedule and the live remaining time")
    func projectedFinish() {
        let head = QueueWidgetNow(id: UUID(), title: "A", duration: 15 * 60, difficulty: .medium)
        let next = QueueWidgetUpcoming(id: UUID(), title: "B", duration: 20 * 60)
        let queue = QueueWidgetSnapshot(
            now: head,
            upNext: [next],
            doneToday: 0,
            plannedToday: 2,
            minutesFocusedToday: 0,
            updatedAt: now
        )

        let idleFinish = QueueWidgetProjection.projectedFinish(queue: queue, focus: nil, at: now)
        #expect(idleFinish == now.addingTimeInterval(35 * 60))

        let focus = focusSnapshot(taskID: head.id, state: .running, planned: 15 * 60, elapsed: 10 * 60)
        let liveFinish = QueueWidgetProjection.projectedFinish(queue: queue, focus: focus, at: now)
        #expect(liveFinish == now.addingTimeInterval(25 * 60))
        #expect(QueueWidgetProjection.projectedFinish(
            queue: QueueWidgetSnapshot(
                now: nil,
                upNext: [],
                doneToday: 0,
                plannedToday: 0,
                minutesFocusedToday: 0,
                updatedAt: now
            ),
            focus: nil,
            at: now
        ) == nil)
    }

    @Test("Snapshot round-trips through the App Group defaults")
    func storeRoundTrip() {
        let defaults = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuite) }
        QueueActivityStore.clear(defaults: defaults)
        let snapshot = QueueWidgetSnapshotBuilder.make(
            tasks: [task(title: "Pause check", position: 0, duration: 15 * 60)],
            at: now,
            calendar: calendar
        )
        QueueActivityStore.save(snapshot, defaults: defaults)
        let loaded = QueueActivityStore.load(defaults: defaults)
        #expect(loaded == snapshot)
        QueueActivityStore.clear(defaults: defaults)
        #expect(QueueActivityStore.load(defaults: defaults) == nil)
    }

    @Test("Widget edits bump a generation the app can observe")
    func generationBump() {
        let defaults = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuite) }
        #expect(WidgetStoreGeneration.current(defaults: defaults) == 0)
        #expect(WidgetStoreGeneration.bump(defaults: defaults) == 1)
        #expect(WidgetStoreGeneration.bump(defaults: defaults) == 2)
        #expect(WidgetStoreGeneration.current(defaults: defaults) == 2)
    }

    @Test("Migration waits to open the shared store until the app has prepared it")
    func migrationPolicy() {
        #expect(AppGroupStoreMigration.shouldCopyLegacyStore(
            legacyExists: true,
            destinationExists: false,
            markerExists: false
        ))
        #expect(!AppGroupStoreMigration.shouldCopyLegacyStore(
            legacyExists: true,
            destinationExists: true,
            markerExists: false
        ))
        #expect(!AppGroupStoreMigration.shouldCopyLegacyStore(
            legacyExists: false,
            destinationExists: false,
            markerExists: false
        ))
        #expect(!AppGroupStoreMigration.widgetMayOpenStore(appGroupAvailable: true, markerExists: false))
        #expect(AppGroupStoreMigration.widgetMayOpenStore(appGroupAvailable: true, markerExists: true))
        #expect(AppGroupStoreMigration.widgetMayOpenStore(appGroupAvailable: false, markerExists: false))
    }

    private let defaultsSuite = "queue.widget.tests"

    private func isolatedDefaults() -> UserDefaults {
        let defaults = UserDefaults(suiteName: defaultsSuite)!
        defaults.removePersistentDomain(forName: defaultsSuite)
        return defaults
    }

    private func task(
        title: String,
        position: Int,
        duration: TimeInterval = 15 * 60,
        difficulty: TaskDifficulty = .medium,
        status: TaskStatus = .queued,
        completedAt: Date? = nil,
        focus: TimeInterval = 0
    ) -> QueueTask {
        QueueTask(
            title: title,
            estimatedDuration: duration,
            difficulty: difficulty,
            createdAt: now.addingTimeInterval(TimeInterval(position)),
            queuePosition: position,
            status: status,
            completedAt: completedAt,
            actualFocusDuration: focus,
            modifiedAt: now
        )
    }

    private func focusSnapshot(
        taskID: UUID,
        state: FocusTimerState,
        planned: TimeInterval = 15 * 60,
        elapsed: TimeInterval = 0
    ) -> FocusWidgetSnapshot {
        let session = FocusSession(
            taskID: taskID,
            sessionStart: now.addingTimeInterval(-elapsed),
            segmentStart: state == .running ? now.addingTimeInterval(-elapsed) : now,
            plannedDuration: planned,
            accumulatedActive: state == .running ? 0 : elapsed,
            state: state
        )
        return FocusWidgetSnapshot(
            taskID: taskID,
            taskTitle: "Write",
            difficultyDisplayName: "Medium",
            estimatedDuration: planned,
            session: session,
            updatedAt: now
        )
    }
}
