import Foundation
import Testing
@testable import QueueCore

@Suite("Next block after a celebration")
struct NextBlockPlannerTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("The next task is the earliest queued block, not the one that just finished")
    func picksEarliestQueued() {
        let finished = task("Finished", position: 0, status: .completed, created: 1)
        let skipped = task("Skipped", position: 1, status: .skipped, created: 2)
        let review = task("Review", position: 2, status: .review, created: 3)
        let archived = task("Archived", position: 3, status: .archived, created: 4)
        let focusing = task("Still focusing", position: 4, status: .active, created: 5)
        let paused = task("Paused", position: 5, status: .paused, created: 6)
        let expired = task("Expired", position: 6, status: .expired, created: 7)
        let later = task("Later", position: 9, status: .queued, created: 9)
        let samePositionLater = task("Same position later", position: 8, status: .queued, created: 11)
        let next = task("Outline", position: 8, status: .queued, created: 8)

        let tasks = [later, finished, skipped, samePositionLater, review, next, archived, focusing, paused, expired]
        let picked = NextBlockPlanner.nextTask(after: finished.id, in: tasks)
        #expect(picked?.id == next.id)
        #expect(picked?.title == "Outline")
    }

    @Test("A block that is still marked queued is not offered as its own next task")
    func excludesTheFinishedIdentity() {
        let current = task("Current", position: 0, status: .queued, created: 1)
        let following = task("Following", position: 1, status: .queued, created: 2)
        let picked = NextBlockPlanner.nextTask(after: current.id, in: [following, current])
        #expect(picked?.id == following.id)
    }

    @Test("No queued task means the celebration finishes without a next block")
    func nothingQueued() {
        let finished = task("Finished", position: 0, status: .completed, created: 1)
        let skipped = task("Skipped", position: 1, status: .skipped, created: 2)
        #expect(NextBlockPlanner.nextTask(after: finished.id, in: [finished, skipped]) == nil)
        #expect(NextBlockPlanner.offer(after: finished.id, in: [finished], autoStartNextTask: true) == nil)
        #expect(NextBlockPlanner.offer(after: finished.id, in: [], autoStartNextTask: false) == nil)
    }

    @Test("Auto-start is a short countdown only when the preference is on and a task is waiting")
    func autoStartPreference() {
        let finished = task("Finished", position: 0, status: .completed, created: 1)
        let next = task("Outline", position: 1, status: .queued, created: 2)

        let manual = NextBlockPlanner.offer(after: finished.id, in: [finished, next], autoStartNextTask: false)
        #expect(manual?.task.id == next.id)
        #expect(manual?.willAutoStart == false)
        #expect(manual?.autoStartCountdown == nil)
        #expect(manual?.breakDuration == NextBlockPlanner.breakDuration)
        #expect(NextBlockPlanner.breakDuration == 300)

        let automatic = NextBlockPlanner.offer(after: finished.id, in: [finished, next], autoStartNextTask: true)
        #expect(automatic?.willAutoStart == true)
        #expect(automatic?.autoStartCountdown == NextBlockPlanner.autoStartCountdown)
        #expect(NextBlockPlanner.autoStartCountdown == 5)
        #expect(automatic?.breakDuration == NextBlockPlanner.breakDuration)
    }

    @Test("Cancelling auto-start keeps the person on the celebration even after the countdown")
    func autoStartDecision() {
        let start = now
        let duration: TimeInterval = 5
        #expect(
            NextBlockHandoffResolver.autoStart(
                cancelled: false,
                startedAt: start,
                duration: duration,
                now: start.addingTimeInterval(4.9)
            ) == .wait
        )
        #expect(
            NextBlockHandoffResolver.autoStart(
                cancelled: false,
                startedAt: start,
                duration: duration,
                now: start.addingTimeInterval(5)
            ) == .startNext
        )
        #expect(
            NextBlockHandoffResolver.autoStart(
                cancelled: true,
                startedAt: start,
                duration: duration,
                now: start.addingTimeInterval(5)
            ) == .stay
        )
        #expect(
            NextBlockHandoffResolver.autoStart(
                cancelled: true,
                startedAt: start,
                duration: duration,
                now: start
            ) == .stay
        )
    }

    @Test("Skipping a break or letting it finish starts the next block. Leaving does not")
    func breakDecision() {
        let start = now
        #expect(NextBlockHandoffResolver.resolveBreak(.skip) == .startNext)
        #expect(NextBlockHandoffResolver.resolveBreak(.finished) == .startNext)
        #expect(NextBlockHandoffResolver.resolveBreak(.leave) == .stay)
        #expect(
            NextBlockHandoffResolver.afterBreak(
                skipped: true,
                startedAt: start,
                duration: 5 * 60,
                now: start.addingTimeInterval(12)
            ) == .startNext
        )
        #expect(
            NextBlockHandoffResolver.afterBreak(
                skipped: false,
                startedAt: start,
                duration: 5 * 60,
                now: start.addingTimeInterval(299)
            ) == .wait
        )
        #expect(
            NextBlockHandoffResolver.afterBreak(
                skipped: false,
                startedAt: start,
                duration: 5 * 60,
                now: start.addingTimeInterval(300)
            ) == .startNext
        )
    }

    @Test("Countdown remaining is derived from the start instant and never goes negative")
    func countdownClock() {
        let start = now
        #expect(CountdownClock.remaining(startedAt: start, duration: 300, now: start.addingTimeInterval(40)) == 260)
        #expect(CountdownClock.remaining(startedAt: start, duration: 300, now: start.addingTimeInterval(400)) == 0)
        #expect(CountdownClock.remaining(startedAt: start, duration: 300, now: start.addingTimeInterval(-10)) == 300)
        #expect(CountdownClock.isComplete(startedAt: start, duration: 300, now: start.addingTimeInterval(299)) == false)
        #expect(CountdownClock.isComplete(startedAt: start, duration: 300, now: start.addingTimeInterval(300)))
        #expect(NextBlockCopy.displayedSeconds(remaining: 4.1) == 5)
        #expect(NextBlockCopy.displayedSeconds(remaining: 0) == 0)
        #expect(NextBlockCopy.displayedSeconds(remaining: -2) == 0)
    }

    @Test("A countdown that has already elapsed finishes without sleeping")
    func waitAlreadyElapsed() async {
        let started = Date().addingTimeInterval(-10)
        let finished = await CountdownClock.waitUntilComplete(startedAt: started, duration: 5)
        #expect(finished)
    }

    @Test("Cancelling a countdown wait does not report completion")
    func waitCancels() async {
        let running = Task {
            await CountdownClock.waitUntilComplete(startedAt: Date(), duration: 30)
        }
        running.cancel()
        let finished = await running.value
        #expect(finished == false)
    }

    @Test("Follow-up labels name the next task and stay free of pressure")
    func calmCopy() {
        #expect(NextBlockCopy.startButtonTitle(taskTitle: "Outline the intro") == "Start next: Outline the intro")
        #expect(NextBlockCopy.breakButtonTitle == "Take a 5-min break first")
        #expect(NextBlockCopy.skipBreakTitle == "Skip break")
        #expect(NextBlockCopy.leaveBreakTitle == "Done for now")
        #expect(NextBlockCopy.cancelAutoStartTitle == "Not now")
        #expect(NextBlockCopy.breakNextLine(taskTitle: "Outline") == "Next up: Outline")
        #expect(NextBlockCopy.autoStartStatus(taskTitle: "Outline", secondsRemaining: 5) == "Starting Outline in 5 seconds")
        #expect(NextBlockCopy.autoStartStatus(taskTitle: "Outline", secondsRemaining: 1) == "Starting Outline in 1 second")
        #expect(NextBlockCopy.autoStartStatus(taskTitle: "Outline", secondsRemaining: 0) == "Starting Outline")

        let samples = [
            NextBlockCopy.startButtonTitle(taskTitle: "Outline"),
            NextBlockCopy.breakButtonTitle,
            NextBlockCopy.skipBreakTitle,
            NextBlockCopy.leaveBreakTitle,
            NextBlockCopy.cancelAutoStartTitle,
            NextBlockCopy.breakHeading,
            NextBlockCopy.breakNextLine(taskTitle: "Outline"),
            NextBlockCopy.autoStartStatus(taskTitle: "Outline", secondsRemaining: 5)
        ]
        let banned = ["streak", "behind", "hurry", "overdue", "failed", "lazy", "must", "should"]
        for sample in samples {
            let lower = sample.lowercased()
            for word in banned {
                #expect(lower.contains(word) == false)
            }
        }
    }

    @Test("Starting the next block replaces the finished block's end alert")
    func alertHandoff() async {
        let finishedID = UUID()
        let nextID = UUID()
        let finished = FocusSession(
            taskID: finishedID,
            sessionStart: now,
            segmentStart: now,
            plannedDuration: 15 * 60,
            accumulatedActive: 15 * 60,
            state: .completed,
            completedAt: now
        )
        let next = FocusSession(
            taskID: nextID,
            sessionStart: now,
            segmentStart: now,
            plannedDuration: 20 * 60,
            state: .running
        )
        let scheduler = RecordingFocusEndNotificationScheduler()
        let sync = FocusEndNotificationSync(scheduler: scheduler)
        await sync.sync(session: finished, taskTitle: "Finished", now: now)
        await sync.sync(session: next, taskTitle: "Outline", now: now)

        let applied = await scheduler.applied
        #expect(applied.count == 2)
        #expect(applied[0] == .cancel(andDelivered: true))
        guard case .schedule(let alert) = applied[1] else {
            Issue.record("The next block should schedule its own alert")
            return
        }
        #expect(alert.taskID == nextID)
        #expect(alert.sessionID == next.id)
        #expect(alert.taskTitle == "Outline")
        #expect(alert.notificationTitle == "Outline")
        #expect(alert.fireDate == now.addingTimeInterval(20 * 60))
        #expect(FocusEndAlert.requestIdentifier == "queue.focus-end")
    }

    @Test("The live widget snapshot names the next block and drops the finished one")
    func widgetNamesTheNextBlock() {
        let finished = task("Finished", position: 0, status: .completed, created: 1)
        let next = task("Outline", position: 1, status: .queued, created: 2)
        let offer = NextBlockPlanner.offer(after: finished.id, in: [finished, next], autoStartNextTask: false)
        let nextSession = FocusSession(
            taskID: next.id,
            sessionStart: now,
            segmentStart: now,
            plannedDuration: next.estimatedDuration,
            state: .running
        )
        let live = FocusWidgetSnapshot.live(task: offer!.task, session: nextSession, updatedAt: now)
        #expect(live?.taskID == next.id)
        #expect(live?.taskTitle == "Outline")
        #expect(live?.session.taskID == next.id)
        #expect(live?.isActivelyTiming == true)
        #expect(live?.estimatedDuration == next.estimatedDuration)

        let finishedSession = FocusSession(
            taskID: finished.id,
            sessionStart: now,
            segmentStart: now,
            plannedDuration: 15 * 60,
            state: .completed,
            completedAt: now
        )
        #expect(FocusWidgetSnapshot.live(task: finished, session: finishedSession, updatedAt: now) == nil)

        let mismatched = FocusWidgetSnapshot.live(task: finished, session: nextSession, updatedAt: now)
        #expect(mismatched == nil)
    }

    private func task(
        _ title: String,
        position: Int,
        status: TaskStatus,
        created: TimeInterval
    ) -> QueueTask {
        QueueTask(
            title: title,
            createdAt: now.addingTimeInterval(created),
            queuePosition: position,
            status: status,
            modifiedAt: now.addingTimeInterval(created)
        )
    }
}
