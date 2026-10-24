import Foundation

/// What a long-press on a stack card can do.
///
/// Skip is the only command that changes queue order. Delete does nothing
/// until `confirmDelete`. Opening, closing, and editing award no XP.
public enum StackPreviewCommand: Equatable, Sendable {
    case openPreview
    case closePreview
    case tapPreview
    case startFocus
    case edit
    case addDetails
    case skipForToday
    case requestDelete
    case confirmDelete
    case cancelDelete
}

public enum StackPreviewEffect: Equatable, Sendable {
    case presented(TaskPreviewContent)
    case dismissed
    case openedTaskPage(TaskPreviewContent)
    case startedFocus(UUID)
    case editing(UUID)
    case addingDetails(UUID)
    case skipped(UUID)
    case deleteNeedsConfirmation(UUID)
    case deleted(UUID)
    case deleteCancelled
    case ignored
}

/// Domain stand-in for the stack card's long-press menu.
///
/// The view calls the same outcomes through the app repository: start runs
/// that task, skip is the order change, and delete waits for the confirmation
/// dialog. This session is what the tests drive.
public actor StackPreviewSession {
    private let queue: TaskQueueService
    private let timer: FocusTimerEngine
    private let rewards: RewardEngine
    public private(set) var presentedTaskID: UUID?
    public private(set) var pendingDeleteID: UUID?
    /// XP added by preview commands. Stays zero; completion is a different path.
    public private(set) var awardedDuringPreview: Int = 0

    public init(queue: TaskQueueService, timer: FocusTimerEngine, rewards: RewardEngine) {
        self.queue = queue
        self.timer = timer
        self.rewards = rewards
    }

    /// Long-press (or the VoiceOver Preview action) for one card.
    /// The content is that task only, in its current queue place.
    public func longPress(taskID: UUID) async throws -> TaskPreviewContent {
        let content = try await content(for: taskID)
        presentedTaskID = taskID
        return content
    }

    @discardableResult
    public func perform(_ command: StackPreviewCommand, taskID: UUID) async throws -> StackPreviewEffect {
        let before = await rewards.totalXP()
        let effect = try await apply(command, taskID: taskID)
        let after = await rewards.totalXP()
        if after > before {
            awardedDuringPreview += after - before
        }
        return effect
    }

    // MARK: - Private

    private func apply(_ command: StackPreviewCommand, taskID: UUID) async throws -> StackPreviewEffect {
        switch command {
        case .openPreview:
            let content = try await content(for: taskID)
            presentedTaskID = taskID
            return .presented(content)
        case .closePreview:
            presentedTaskID = nil
            return .dismissed
        case .tapPreview:
            let content = try await content(for: taskID)
            return .openedTaskPage(content)
        case .startFocus:
            try await startFocus(taskID: taskID)
            return .startedFocus(taskID)
        case .edit:
            return .editing(taskID)
        case .addDetails:
            return .addingDetails(taskID)
        case .skipForToday:
            _ = try await queue.skip(id: taskID)
            if presentedTaskID == taskID { presentedTaskID = nil }
            if pendingDeleteID == taskID { pendingDeleteID = nil }
            return .skipped(taskID)
        case .requestDelete:
            pendingDeleteID = taskID
            return .deleteNeedsConfirmation(taskID)
        case .confirmDelete:
            guard pendingDeleteID == taskID else { return .ignored }
            pendingDeleteID = nil
            _ = try await queue.archive(id: taskID)
            if presentedTaskID == taskID { presentedTaskID = nil }
            return .deleted(taskID)
        case .cancelDelete:
            pendingDeleteID = nil
            return .deleteCancelled
        }
    }

    private func content(for taskID: UUID) async throws -> TaskPreviewContent {
        let ordered = await queue.activeQueue()
        guard let index = ordered.firstIndex(where: { $0.id == taskID }) else {
            throw TaskTransitionError.taskNotFound
        }
        return TaskPreviewContent(task: ordered[index], position: index + 1)
    }

    /// Starts this task and its timer. Does not move it, and does not start a neighbour.
    private func startFocus(taskID: UUID) async throws {
        guard let task = await queue.task(id: taskID) else {
            throw TaskTransitionError.taskNotFound
        }
        switch task.status {
        case .queued, .expired:
            _ = try await queue.start(id: taskID)
        case .paused:
            _ = try await queue.resume(id: taskID)
        case .active:
            break
        default:
            throw TaskTransitionError.invalidTransition(from: task.status, to: .active)
        }
        if let session = await timer.currentSession(),
           session.taskID == taskID,
           session.state == .running || session.state == .paused {
            return
        }
        _ = try await timer.start(taskID: taskID, plannedDuration: task.estimatedDuration)
    }
}
