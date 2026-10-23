import Foundation
import SwiftData
import QueueCore
@testable import Queue

/// One place to build a task. A new stored field is added here, then the
/// migration sample and the functional tests pick it up.
enum QueueTestFixture {
    static func makeTask(
        id: UUID = UUID(),
        title: String,
        notes: String? = nil,
        estimatedDuration: TimeInterval = QueueTask.defaultEstimatedDuration,
        difficulty: TaskDifficulty = .medium,
        plannedStartAt: Date? = nil,
        createdAt: Date = Date(timeIntervalSince1970: 1_700_000_000),
        scheduledDate: Date? = nil,
        queuePosition: Int = 0,
        status: TaskStatus = .queued,
        startedAt: Date? = nil,
        completedAt: Date? = nil,
        actualFocusDuration: TimeInterval = 0,
        accumulatedPausedDuration: TimeInterval = 0,
        extensions: [TimerExtension] = [],
        category: String? = nil,
        calendarEventID: String? = nil,
        xpAwardID: UUID? = nil,
        modifiedAt: Date = Date(timeIntervalSince1970: 1_700_000_000)
    ) -> QueueTask {
        QueueTask(
            id: id,
            title: title,
            notes: notes,
            estimatedDuration: estimatedDuration,
            difficulty: difficulty,
            plannedStartAt: plannedStartAt,
            createdAt: createdAt,
            scheduledDate: scheduledDate,
            queuePosition: queuePosition,
            status: status,
            startedAt: startedAt,
            completedAt: completedAt,
            actualFocusDuration: actualFocusDuration,
            accumulatedPausedDuration: accumulatedPausedDuration,
            extensions: extensions,
            category: category,
            calendarEventID: calendarEventID,
            xpAwardID: xpAwardID,
            modifiedAt: modifiedAt
        )
    }

    static func temporaryDirectory(prefix: String = "queue-tests") throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func storeURL(in directory: URL) -> URL {
        directory.appendingPathComponent("QueueLocalStore.store")
    }

    static func remove(_ directory: URL) {
        try? FileManager.default.removeItem(at: directory)
    }
}

/// In-memory or on-disk repository wired the way the app wires it, with a
/// controllable clock and a recording focus-end scheduler.
@MainActor
final class QueueHarness {
    let container: ModelContainer
    let clock: ControllableClock
    let scheduler: RecordingFocusEndNotificationScheduler
    let repository: TaskRepository

    private init(
        container: ModelContainer,
        clock: ControllableClock,
        scheduler: RecordingFocusEndNotificationScheduler,
        repository: TaskRepository
    ) {
        self.container = container
        self.clock = clock
        self.scheduler = scheduler
        self.repository = repository
    }

    static func inMemory(clock: ControllableClock = ControllableClock(start: Date())) throws -> QueueHarness {
        try make(container: AppModelContainer.makeInMemory(), clock: clock)
    }

    static func persistent(
        at url: URL,
        clock: ControllableClock = ControllableClock(start: Date())
    ) throws -> QueueHarness {
        try make(container: AppModelContainer.makePersistent(storeURL: url), clock: clock)
    }

    /// A second repository on the same container, as a widget process would
    /// after the app has saved. It does not share the in-memory timer or ledger.
    func reopenedRepository() -> TaskRepository {
        Self.makeRepository(container: container, clock: clock, scheduler: scheduler)
    }

    func storedTransactions() throws -> [XPTransaction] {
        let context = ModelContext(container)
        return try context.fetch(FetchDescriptor<XPTransactionEntity>()).compactMap { $0.asDomain() }
    }

    func storedTotalXP() throws -> Int {
        try storedTransactions().reduce(0) { $0 + $1.amount }
    }

    func sourceEventIDs() throws -> Set<UUID> {
        Set(try storedTransactions().map(\.sourceEventID))
    }

    func storedSessions() throws -> [FocusSession] {
        let context = ModelContext(container)
        return try context.fetch(FetchDescriptor<FocusSessionEntity>()).compactMap { $0.asDomain() }
    }

    private static func make(container: ModelContainer, clock: ControllableClock) throws -> QueueHarness {
        let scheduler = RecordingFocusEndNotificationScheduler()
        let repository = makeRepository(container: container, clock: clock, scheduler: scheduler)
        return QueueHarness(
            container: container,
            clock: clock,
            scheduler: scheduler,
            repository: repository
        )
    }

    private static func makeRepository(
        container: ModelContainer,
        clock: ControllableClock,
        scheduler: RecordingFocusEndNotificationScheduler
    ) -> TaskRepository {
        TaskRepository(
            context: ModelContext(container),
            queueService: TaskQueueService(clock: clock),
            timerEngine: FocusTimerEngine(clock: clock),
            rewardEngine: RewardEngine(clock: clock),
            focusNotifications: scheduler,
            notificationAuthorizer: SilentFocusNotificationAuthorizer()
        )
    }
}

/// The same calls `RepositoryFocusMutator` makes. Widget and Lock Screen
/// intents both end in these methods.
struct RepositoryFocusCalls: WidgetFocusMutating {
    let repository: TaskRepository

    func startFocus(taskID: UUID, plannedDuration: TimeInterval) async throws {
        _ = try await repository.beginFocus(taskID: taskID, plannedDuration: plannedDuration)
    }

    func pauseFocus(taskID: UUID) async throws {
        _ = try await repository.pauseFocus(taskID: taskID)
    }

    func resumeFocus(taskID: UUID) async throws {
        _ = try await repository.resumeFocus(taskID: taskID)
    }

    func completeFocus(taskID: UUID) async throws {
        _ = try await repository.completeFocus(taskID: taskID)
    }

    func extendFocus(by duration: TimeInterval) async throws {
        _ = try await repository.extendFocus(by: duration)
    }
}
