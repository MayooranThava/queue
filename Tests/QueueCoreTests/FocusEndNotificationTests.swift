import Foundation
import Testing
@testable import QueueCore

@Suite("Focus end alerts")
struct FocusEndNotificationTests {
    @Test("A running block schedules one alert named for the task")
    func schedulesNamedAlert() async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let session = try await runningSession(planned: 15 * 60, now: now)
        let command = FocusEndAlertPlanner.command(session: session, taskTitle: "  Outline the intro  ", now: now)

        guard case .schedule(let alert) = command else {
            Issue.record("Expected a scheduled alert")
            return
        }
        #expect(alert.taskID == session.taskID)
        #expect(alert.sessionID == session.id)
        #expect(alert.notificationTitle == "Outline the intro")
        #expect(alert.notificationBody == "Time’s up — finish when you’re ready.")
        #expect(alert.fireDate == now.addingTimeInterval(15 * 60))
        #expect(FocusEndAlert.requestIdentifier == "queue.focus-end")
    }

    @Test("An empty title falls back without dropping the alert")
    func emptyTitle() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let session = FocusSession(
            taskID: UUID(),
            sessionStart: now,
            segmentStart: now,
            plannedDuration: 60,
            state: .running
        )
        let command = FocusEndAlertPlanner.command(session: session, taskTitle: "   ", now: now)
        guard case .schedule(let alert) = command else {
            Issue.record("Expected a scheduled alert")
            return
        }
        #expect(alert.notificationTitle == "Focus block")
    }

    @Test("Pause cancels, resume and +5 minutes move the fire date, complete clears it")
    func pauseResumeExtendComplete() async throws {
        let clock = ControllableClock()
        let engine = FocusTimerEngine(clock: clock)
        let scheduler = RecordingFocusEndNotificationScheduler()
        let sync = FocusEndNotificationSync(scheduler: scheduler)
        let taskID = UUID()
        let title = "Ship the notes"

        var session = try await engine.start(taskID: taskID, plannedDuration: 20 * 60)
        let startedAt = clock.now()
        await sync.sync(session: session, taskTitle: title, now: startedAt)

        clock.advance(by: 5 * 60)
        session = try await engine.pause()
        await sync.sync(session: session, taskTitle: title, now: clock.now())

        clock.advance(by: 10 * 60)
        session = try await engine.resume()
        let resumedAt = clock.now()
        await sync.sync(session: session, taskTitle: title, now: resumedAt)

        session = try await engine.extend(by: 5 * 60)
        let extendedAt = clock.now()
        await sync.sync(session: session, taskTitle: title, now: extendedAt)

        _ = try await engine.complete()
        let completed = await engine.currentSession()
        await sync.sync(session: completed, taskTitle: title, now: clock.now())

        let applied = await scheduler.applied
        #expect(applied.count == 5)

        guard case .schedule(let started) = applied[0] else {
            Issue.record("Start should schedule")
            return
        }
        #expect(started.notificationTitle == title)
        #expect(started.fireDate == startedAt.addingTimeInterval(20 * 60))

        #expect(applied[1] == .cancel(andDelivered: false))

        guard case .schedule(let resumed) = applied[2] else {
            Issue.record("Resume should schedule the time still left")
            return
        }
        #expect(resumed.fireDate == resumedAt.addingTimeInterval(15 * 60))
        #expect(resumed.sessionID == started.sessionID)

        guard case .schedule(let extended) = applied[3] else {
            Issue.record("+5 minutes should replace the pending alert")
            return
        }
        #expect(extended.fireDate == extendedAt.addingTimeInterval(20 * 60))
        #expect(extended.fireDate == resumed.fireDate.addingTimeInterval(5 * 60))

        #expect(applied[4] == .cancel(andDelivered: true))
        #expect(pendingAlert(after: [applied[0]])?.fireDate == started.fireDate)
        #expect(pendingAlert(after: Array(applied.prefix(2))) == nil)
        #expect(pendingAlert(after: Array(applied.prefix(4)))?.fireDate == extended.fireDate)
        #expect(pendingAlert(after: applied) == nil)
    }

    @Test("Extending an expired block schedules the new end and keeps the task name")
    func extendAfterExpiry() async throws {
        let clock = ControllableClock()
        let engine = FocusTimerEngine(clock: clock)
        let scheduler = RecordingFocusEndNotificationScheduler()
        let sync = FocusEndNotificationSync(scheduler: scheduler)

        _ = try await engine.start(taskID: UUID(), plannedDuration: 30)
        clock.advance(by: 30)
        let expired = await engine.evaluateExpiry()
        await sync.sync(session: expired, taskTitle: "Read the brief", now: clock.now())

        let extended = try await engine.extend(by: 5 * 60)
        let extendedAt = clock.now()
        await sync.sync(session: extended, taskTitle: "Read the brief", now: extendedAt)

        let applied = await scheduler.applied
        #expect(applied[0] == .leaveScheduledAlert)
        guard case .schedule(let alert) = applied[1] else {
            Issue.record("Expected a rescheduled alert")
            return
        }
        #expect(alert.notificationTitle == "Read the brief")
        #expect(alert.fireDate == extendedAt.addingTimeInterval(5 * 60))
        #expect(extended.state == .running)
    }

    @Test("Skip, delete, and a missing session cancel so a stale alert cannot fire")
    func sessionEndCancels() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let session = FocusSession(
            taskID: UUID(),
            sessionStart: now,
            segmentStart: now,
            plannedDuration: 60,
            state: .running
        )
        #expect(FocusEndAlertPlanner.command(session: nil, taskTitle: "Gone", now: now) == .cancel(andDelivered: true))
        #expect(FocusEndAlertPlanner.command(session: paused(session, now: now), taskTitle: "Gone", now: now) == .cancel(andDelivered: false))
        #expect(FocusEndAlertPlanner.command(session: completed(session, now: now), taskTitle: "Gone", now: now) == .cancel(andDelivered: true))
    }

    @Test("Expiry leaves the scheduled alert in place")
    func expiryLeavesAlert() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let session = FocusSession(
            taskID: UUID(),
            sessionStart: now.addingTimeInterval(-60),
            segmentStart: now.addingTimeInterval(-60),
            plannedDuration: 60,
            accumulatedActive: 60,
            state: .expired
        )
        #expect(FocusEndAlertPlanner.command(session: session, taskTitle: "Done waiting", now: now) == .leaveScheduledAlert)
    }

    @Test("Permission is requested from onboarding or focus start, never a cold launch")
    func permissionPromptPolicy() {
        #expect(FocusNotificationPermissionPolicy.shouldRequest(status: .notDetermined, reason: .coldLaunch) == false)
        #expect(FocusNotificationPermissionPolicy.shouldRequest(status: .notDetermined, reason: .sessionRestore) == false)
        #expect(FocusNotificationPermissionPolicy.shouldRequest(status: .notDetermined, reason: .onboardingOptIn))
        #expect(FocusNotificationPermissionPolicy.shouldRequest(status: .notDetermined, reason: .focusStartOrResume))
        #expect(FocusNotificationPermissionPolicy.shouldRequest(status: .denied, reason: .focusStartOrResume) == false)
        #expect(FocusNotificationPermissionPolicy.shouldRequest(status: .authorized, reason: .onboardingOptIn) == false)
        #expect(FocusNotificationPermissionPolicy.canSchedule(status: .authorized))
        #expect(FocusNotificationPermissionPolicy.canSchedule(status: .denied) == false)
        #expect(FocusNotificationPermissionPolicy.canSchedule(status: .notDetermined) == false)
    }

    @Test("The alert link names the focus task and round-trips")
    func deepLinkRoundTrip() {
        let taskID = UUID()
        let url = FocusEndDeepLink.url(taskID: taskID)
        #expect(url.scheme == FocusEndDeepLink.scheme)
        #expect(url.host == FocusEndDeepLink.focusHost)
        #expect(FocusEndDeepLink.isFocus(url))
        #expect(FocusEndDeepLink.taskID(from: url) == taskID)
        #expect(FocusEndDeepLink.taskID(from: URL(string: "queueapp://queue")!) == nil)
        #expect(FocusEndDeepLink.taskID(from: URL(string: "queueapp://focus")!) == nil)
    }

    /// Mirrors the single pending request: schedule replaces, cancel clears, expiry leaves it.
    private func pendingAlert(after commands: [FocusEndNotificationCommand]) -> FocusEndAlert? {
        var pending: FocusEndAlert?
        for command in commands {
            switch command {
            case .schedule(let alert):
                pending = alert
            case .cancel:
                pending = nil
            case .leaveScheduledAlert:
                break
            }
        }
        return pending
    }

    private func runningSession(planned: TimeInterval, now: Date) async throws -> FocusSession {
        let clock = ControllableClock(start: now)
        let engine = FocusTimerEngine(clock: clock)
        return try await engine.start(taskID: UUID(), plannedDuration: planned)
    }

    private func paused(_ session: FocusSession, now: Date) -> FocusSession {
        var copy = session
        copy.accumulatedActive = 10
        copy.segmentStart = now
        copy.state = .paused
        return copy
    }

    private func completed(_ session: FocusSession, now: Date) -> FocusSession {
        var copy = session
        copy.state = .completed
        copy.completedAt = now
        return copy
    }
}
