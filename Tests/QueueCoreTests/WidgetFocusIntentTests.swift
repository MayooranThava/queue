import Foundation
import Testing
@testable import QueueCore

@Suite("Widget focus intents")
struct WidgetFocusIntentTests {
    private let taskID = UUID()
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("Start, pause, resume, done, and +5 route to the shared focus commands")
    func routesToSharedCommands() {
        let queue = QueueWidgetSnapshot(
            now: QueueWidgetNow(id: taskID, title: "Update résumé", duration: 15 * 60, difficulty: .medium),
            upNext: [],
            doneToday: 1,
            plannedToday: 2,
            minutesFocusedToday: 15,
            updatedAt: now
        )

        #expect(
            WidgetFocusRouting.command(for: .startNext, queue: queue, focus: nil)
                == .startNext(taskID: taskID, plannedDuration: 15 * 60)
        )
        #expect(WidgetFocusRouting.command(for: .startNext, queue: nil, focus: nil) == nil)
        #expect(WidgetFocusRouting.command(
            for: .startNext,
            queue: QueueWidgetSnapshot(
                now: nil,
                upNext: [],
                doneToday: 0,
                plannedToday: 0,
                minutesFocusedToday: 0,
                updatedAt: now
            ),
            focus: nil
        ) == nil)

        let running = focus(state: .running)
        #expect(WidgetFocusRouting.command(for: .startNext, queue: queue, focus: running) == nil)
        #expect(WidgetFocusRouting.command(for: .pauseOrResume, queue: queue, focus: running) == .pause(taskID: taskID))
        #expect(WidgetFocusRouting.command(for: .complete, queue: queue, focus: running) == .complete(taskID: taskID))
        #expect(
            WidgetFocusRouting.command(for: .extendFiveMinutes, queue: queue, focus: running)
                == .extend(taskID: taskID, by: 5 * 60)
        )

        let paused = focus(state: .paused)
        #expect(WidgetFocusRouting.command(for: .pauseOrResume, queue: queue, focus: paused) == .resume(taskID: taskID))
        #expect(WidgetFocusRouting.command(for: .pauseOrResume, queue: queue, focus: focus(state: .expired)) == nil)
        #expect(WidgetFocusRouting.command(for: .complete, queue: queue, focus: nil) == nil)
        #expect(WidgetFocusRouting.command(for: .extendFiveMinutes, queue: queue, focus: nil) == nil)
        #expect(WidgetFocusRouting.fiveMinutes == 5 * 60)
    }

    @Test("Each command calls only the matching focus method")
    func performerUsesSharedPaths() async throws {
        let spy = SpyFocusMutator()
        try await WidgetFocusIntentPerformer.perform(
            .startNext(taskID: taskID, plannedDuration: 15 * 60),
            using: spy
        )
        try await WidgetFocusIntentPerformer.perform(.pause(taskID: taskID), using: spy)
        try await WidgetFocusIntentPerformer.perform(.resume(taskID: taskID), using: spy)
        try await WidgetFocusIntentPerformer.perform(.complete(taskID: taskID), using: spy)
        try await WidgetFocusIntentPerformer.perform(.extend(taskID: taskID, by: 5 * 60), using: spy)

        #expect(spy.calls == [
            .start(taskID, 15 * 60 as TimeInterval),
            .pause(taskID),
            .resume(taskID),
            .complete(taskID),
            .extend(5 * 60 as TimeInterval)
        ])
    }

    @Test("A routed widget action performs the one shared focus call")
    func routedActionPerformsSingleCall() async throws {
        let queue = QueueWidgetSnapshot(
            now: QueueWidgetNow(id: taskID, title: "Update résumé", duration: 20 * 60, difficulty: .hard),
            upNext: [],
            doneToday: 0,
            plannedToday: 1,
            minutesFocusedToday: 0,
            updatedAt: now
        )
        let command = try #require(WidgetFocusRouting.command(for: .startNext, queue: queue, focus: nil))
        let spy = SpyFocusMutator()
        try await WidgetFocusIntentPerformer.perform(command, using: spy)
        #expect(spy.calls == [.start(taskID, 20 * 60 as TimeInterval)])
    }

    private func focus(state: FocusTimerState) -> FocusWidgetSnapshot {
        let session = FocusSession(
            taskID: taskID,
            sessionStart: now,
            segmentStart: now,
            plannedDuration: 15 * 60,
            state: state
        )
        return FocusWidgetSnapshot(
            taskID: taskID,
            taskTitle: "Update résumé",
            difficultyDisplayName: "Medium",
            estimatedDuration: 15 * 60,
            session: session,
            updatedAt: now
        )
    }
}

private final class SpyFocusMutator: WidgetFocusMutating {
    enum Call: Equatable {
        case start(UUID, TimeInterval)
        case pause(UUID)
        case resume(UUID)
        case complete(UUID)
        case extend(TimeInterval)
    }

    private(set) var calls: [Call] = []

    func startFocus(taskID: UUID, plannedDuration: TimeInterval) async throws {
        calls.append(.start(taskID, plannedDuration))
    }

    func pauseFocus(taskID: UUID) async throws {
        calls.append(.pause(taskID))
    }

    func resumeFocus(taskID: UUID) async throws {
        calls.append(.resume(taskID))
    }

    func completeFocus(taskID: UUID) async throws {
        calls.append(.complete(taskID))
    }

    func extendFocus(by duration: TimeInterval) async throws {
        calls.append(.extend(duration))
    }
}
