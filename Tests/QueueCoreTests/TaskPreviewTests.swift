import Foundation
import Testing
@testable import QueueCore

@Suite("Stack card preview")
struct TaskPreviewTests {
    @Test("Preview content keeps the first three lines and explains empty notes")
    func truncationAndEmptyNotes() {
        let notes = """
        - Draft the intro
        2. Write two paragraphs
        • Cut the middle
        Read it aloud
        Why it matters: The draft is blocking the launch
        """
        let task = QueueTask(
            title: "Ship the notes",
            notes: notes,
            estimatedDuration: 25 * 60,
            difficulty: .hard,
            category: " Writing "
        )
        let content = TaskPreviewContent(task: task, position: 3)
        #expect(content.steps == [
            "Draft the intro",
            "Write two paragraphs",
            "Cut the middle"
        ])
        #expect(content.steps.count == TaskPreviewContent.maxVisibleSteps)
        #expect(content.allSteps == [
            "Draft the intro",
            "Write two paragraphs",
            "Cut the middle",
            "Read it aloud"
        ])
        #expect(content.showsOverflow)
        #expect(content.whatToDoLines == [
            "Draft the intro",
            "Write two paragraphs",
            "Cut the middle",
            TaskPreviewContent.overflowMark
        ])
        #expect(content.whyItMatters == "The draft is blocking the launch")
        #expect(!content.allSteps.contains(content.whyItMatters ?? ""))
        #expect(content.metaLine == "25 min · Hard · Writing")
        #expect(content.skillTag == "Writing")
        #expect(content.positionLabel == "#3 in your queue")
        #expect(!content.showsEmptyDetails)

        let exact = TaskPreviewContent(
            task: QueueTask(title: "Three", notes: "One\nTwo\nThree"),
            position: 1
        )
        #expect(exact.steps == ["One", "Two", "Three"])
        #expect(!exact.showsOverflow)
        #expect(exact.whatToDoLines == ["One", "Two", "Three"])

        let wrapped = TaskPreviewContent(
            task: QueueTask(title: "CRLF", notes: "One\r\nTwo\r\nThree\r\nFour"),
            position: 1
        )
        #expect(wrapped.steps == ["One", "Two", "Three"])
        #expect(wrapped.showsOverflow)
        #expect(wrapped.allSteps.count == 4)

        let headed = TaskPreviewContent(
            task: QueueTask(
                title: "Headed",
                notes: "Draft the intro\n\nWhy it matters\nShips the release"
            ),
            position: 2
        )
        #expect(headed.steps == ["Draft the intro"])
        #expect(headed.whyItMatters == "Ships the release")
        #expect(!headed.showsOverflow)
        #expect(!headed.showsEmptyDetails)

        let whyOnly = TaskPreviewContent(
            task: QueueTask(title: "Why", notes: "Why: Keeps the launch honest"),
            position: 1
        )
        #expect(whyOnly.steps.isEmpty)
        #expect(whyOnly.whyItMatters == "Keeps the launch honest")
        #expect(!whyOnly.showsEmptyDetails)

        let unskilled = TaskPreviewContent(
            task: QueueTask(
                title: "Plain",
                notes: "One",
                estimatedDuration: 10 * 60,
                difficulty: .easy,
                category: " "
            ),
            position: 1
        )
        #expect(unskilled.metaLine == "10 min · Easy")
        #expect(unskilled.skillTag == nil)

        let blanks: [String?] = [nil, "", "   ", "\n\n"]
        for notes in blanks {
            let empty = TaskPreviewContent(
                task: QueueTask(title: "Empty", notes: notes),
                position: 4
            )
            #expect(empty.showsEmptyDetails)
            #expect(empty.steps.isEmpty)
            #expect(empty.allSteps.isEmpty)
            #expect(empty.whyItMatters == nil)
            #expect(empty.whatToDoLines.isEmpty)
            #expect(empty.positionLabel == "#4 in your queue")
            #expect(TaskPreviewContent.emptyDetailsMessage == "No details yet")
            #expect(TaskPreviewContent.addDetailsTitle == "Add details")
        }
    }

    @Test("Start focus from the preview menu starts that exact task")
    func startFocusStartsThatTask() async throws {
        let harness = try await PreviewHarness.make(rewards: false)
        let queue = harness.queue
        let first = try await queue.createTask(title: "Alpha outline", estimatedDuration: 10 * 60)
        let middle = try await queue.createTask(title: "Beta research", estimatedDuration: 20 * 60)
        let chosen = try await queue.createTask(title: "Gamma review", estimatedDuration: 30 * 60)
        let before = await queue.activeQueue().map(\.id)

        let effect = try await harness.session.perform(.startFocus, taskID: chosen.id)

        let active = await queue.activeQueue()
        let session = await harness.timer.currentSession()
        #expect(effect == .startedFocus(chosen.id))
        #expect(await queue.activeTask()?.id == chosen.id)
        #expect(session?.taskID == chosen.id)
        #expect(session?.plannedDuration == chosen.estimatedDuration)
        #expect(session?.state == .running)
        #expect(active.map(\.id) == before)
        #expect(active.map(\.id) == [first.id, middle.id, chosen.id])
        #expect(active[0].status == .queued)
        #expect(active[1].status == .queued)
        #expect(active[2].status == .active)
        #expect(await harness.rewards.totalXP() == 0)
        #expect(await harness.session.awardedDuringPreview == 0)
    }

    @Test("Skip is the only preview action that changes queue order, and opening awards no XP")
    func skipAloneChangesOrderAndPreviewAwardsNoXP() async throws {
        let harness = try await PreviewHarness.make(rewards: true)
        let queue = harness.queue
        let first = try await queue.createTask(title: "Alpha outline", notes: "Sketch the outline")
        let middle = try await queue.createTask(title: "Beta research", notes: "Read the paper")
        let last = try await queue.createTask(title: "Gamma review", notes: "Check the launch")
        let order = await queue.activeQueue().map(\.id)
        let statuses = await queue.activeQueue().map(\.status)
        let xp = await harness.rewards.totalXP()
        let transactions = await harness.rewards.transactions().count
        #expect(xp > 0)
        #expect(order == [first.id, middle.id, last.id])

        let stable: [StackPreviewCommand] = [
            .openPreview,
            .closePreview,
            .tapPreview,
            .edit,
            .addDetails,
            .requestDelete,
            .cancelDelete
        ]
        for command in stable {
            _ = try await harness.session.perform(command, taskID: middle.id)
            #expect(await queue.activeQueue().map(\.id) == order)
            #expect(await queue.activeQueue().map(\.status) == statuses)
        }
        #expect(await harness.rewards.totalXP() == xp)
        #expect(await harness.rewards.transactions().count == transactions)
        #expect(await harness.session.awardedDuringPreview == 0)
        #expect(await harness.session.presentedTaskID == nil)
        #expect(await harness.session.pendingDeleteID == nil)

        let skipped = try await harness.session.perform(.skipForToday, taskID: middle.id)
        #expect(skipped == .skipped(middle.id))
        #expect(await queue.activeQueue().map(\.id) == [first.id, last.id])
        #expect(await queue.task(id: middle.id)?.status == .skipped)
        #expect(await queue.activeTask() == nil)
        #expect(await harness.rewards.totalXP() == xp)
        #expect(await harness.rewards.transactions().count == transactions)
        #expect(await harness.session.awardedDuringPreview == 0)
    }

    @Test("Delete happens only after confirmation")
    func deleteWaitsForConfirmation() async throws {
        let harness = try await PreviewHarness.make(rewards: false)
        let queue = harness.queue
        let first = try await queue.createTask(title: "Alpha outline")
        let middle = try await queue.createTask(title: "Beta research")
        let last = try await queue.createTask(title: "Gamma review")
        let order = [first.id, middle.id, last.id]

        let early = try await harness.session.perform(.confirmDelete, taskID: middle.id)
        #expect(early == .ignored)
        #expect(await queue.activeQueue().map(\.id) == order)
        #expect(await queue.task(id: middle.id)?.status == .queued)

        let armed = try await harness.session.perform(.requestDelete, taskID: middle.id)
        #expect(armed == .deleteNeedsConfirmation(middle.id))
        #expect(await harness.session.pendingDeleteID == middle.id)
        #expect(await queue.activeQueue().map(\.id) == order)

        let cancelled = try await harness.session.perform(.cancelDelete, taskID: middle.id)
        #expect(cancelled == .deleteCancelled)
        #expect(await harness.session.pendingDeleteID == nil)
        #expect(await queue.activeQueue().map(\.id) == order)

        let afterCancel = try await harness.session.perform(.confirmDelete, taskID: middle.id)
        #expect(afterCancel == .ignored)
        #expect(await queue.task(id: middle.id)?.status == .queued)

        _ = try await harness.session.perform(.requestDelete, taskID: middle.id)
        let wrong = try await harness.session.perform(.confirmDelete, taskID: first.id)
        #expect(wrong == .ignored)
        #expect(await queue.activeQueue().map(\.id) == order)
        #expect(await harness.session.pendingDeleteID == middle.id)

        let deleted = try await harness.session.perform(.confirmDelete, taskID: middle.id)
        #expect(deleted == .deleted(middle.id))
        #expect(await harness.session.pendingDeleteID == nil)
        #expect(await queue.activeQueue().map(\.id) == [first.id, last.id])
        #expect(await queue.task(id: middle.id)?.status == .archived)
        #expect(await harness.rewards.totalXP() == 0)
    }

    @Test("A long press on any card shows that task's details only")
    func longPressShowsThatCardOnly() async throws {
        let harness = try await PreviewHarness.make(rewards: true)
        let queue = harness.queue
        let alpha = try await queue.createTask(
            title: "Alpha outline",
            notes: "Sketch the outline\nCollect the quotes",
            estimatedDuration: 10 * 60,
            difficulty: .easy,
            category: "Sketching"
        )
        let beta = try await queue.createTask(
            title: "Beta research",
            notes: "Read the paper\nMark the gaps\nWrite the summary\nArchive the clippings",
            estimatedDuration: 20 * 60,
            difficulty: .medium
        )
        let gamma = try await queue.createTask(
            title: "Gamma review",
            notes: "Why it matters: Keeps the launch honest",
            estimatedDuration: 30 * 60,
            difficulty: .hard,
            category: "Review"
        )
        try await queue.reorder(orderedIDs: [gamma.id, alpha.id, beta.id])
        let order = await queue.activeQueue().map(\.id)
        let xp = await harness.rewards.totalXP()
        #expect(order == [gamma.id, alpha.id, beta.id])

        let cards = [gamma, alpha, beta]
        for (offset, task) in cards.enumerated() {
            let pressed = try await harness.session.longPress(taskID: task.id)
            #expect(pressed.taskID == task.id)
            #expect(pressed.title == task.title)
            #expect(pressed.positionLabel == "#\(offset + 1) in your queue")
            #expect(pressed.metaLine == TaskPreviewContent(task: task, position: offset + 1).metaLine)
            let others = cards.filter { $0.id != task.id }
            let rendered = (
                [pressed.title, pressed.metaLine, pressed.positionLabel, pressed.whyItMatters ?? ""]
                    + pressed.allSteps
            ).joined(separator: "\n")
            for other in others {
                #expect(!rendered.contains(other.title))
                #expect(pressed.steps != TaskPreviewContent(task: other, position: 1).steps
                    || pressed.steps.isEmpty)
                #expect(pressed.whyItMatters != TaskPreviewContent(task: other, position: 1).whyItMatters
                    || pressed.whyItMatters == nil)
            }
        }

        let betaPress = try await harness.session.longPress(taskID: beta.id)
        #expect(betaPress.positionLabel == "#3 in your queue")
        #expect(betaPress.steps == ["Read the paper", "Mark the gaps", "Write the summary"])
        #expect(betaPress.showsOverflow)
        #expect(betaPress.whatToDoLines.last == TaskPreviewContent.overflowMark)
        #expect(!betaPress.allSteps.contains("Sketch the outline"))
        #expect(!betaPress.allSteps.contains("Keeps the launch honest"))
        #expect(betaPress.whyItMatters == nil)

        let alphaPress = try await harness.session.longPress(taskID: alpha.id)
        #expect(alphaPress.positionLabel == "#2 in your queue")
        #expect(alphaPress.metaLine == "10 min · Easy · Sketching")
        #expect(alphaPress.steps == ["Sketch the outline", "Collect the quotes"])
        #expect(!alphaPress.showsOverflow)

        let gammaPress = try await harness.session.longPress(taskID: gamma.id)
        #expect(gammaPress.positionLabel == "#1 in your queue")
        #expect(gammaPress.metaLine == "30 min · Hard · Review")
        #expect(gammaPress.steps.isEmpty)
        #expect(gammaPress.whyItMatters == "Keeps the launch honest")
        #expect(!gammaPress.showsEmptyDetails)

        #expect(await queue.activeQueue().map(\.id) == order)
        #expect(await harness.rewards.totalXP() == xp)
        #expect(await harness.session.awardedDuringPreview == 0)
        #expect(await harness.session.presentedTaskID == gamma.id)
    }
}

private struct PreviewHarness {
    let queue: TaskQueueService
    let timer: FocusTimerEngine
    let rewards: RewardEngine
    let session: StackPreviewSession

    static func make(rewards seedXP: Bool) async throws -> PreviewHarness {
        let clock = ControllableClock()
        let queue = TaskQueueService(clock: clock)
        let timer = FocusTimerEngine(clock: clock)
        let rewards = RewardEngine(clock: clock)
        if seedXP {
            _ = await rewards.awardTaskCompletion(
                sourceEventID: UUID(),
                taskID: UUID(),
                difficulty: .medium,
                estimatedDuration: 15 * 60,
                actualFocusDuration: 15 * 60
            )
        }
        let session = StackPreviewSession(queue: queue, timer: timer, rewards: rewards)
        return PreviewHarness(queue: queue, timer: timer, rewards: rewards, session: session)
    }
}
