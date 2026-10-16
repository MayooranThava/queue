import SwiftUI
import SwiftData
import QueueCore

@MainActor
final class AppServices: ObservableObject {
    let queueService: TaskQueueService
    let timerEngine: FocusTimerEngine
    let rewardEngine: RewardEngine
    let analytics: AnalyticsClient
    private(set) var taskRepository: TaskRepository?
    @Published private(set) var totalXP: Int = 0
    @Published private(set) var levelName: String = LevelTable.standard[0].name
    @Published private(set) var undoBannerTitle: String?
    private var undoClearTask: Task<Void, Never>?
    private var didBootstrap = false

    init(
        queueService: TaskQueueService = TaskQueueService(),
        timerEngine: FocusTimerEngine = FocusTimerEngine(),
        rewardEngine: RewardEngine = RewardEngine(),
        analytics: AnalyticsClient = InMemoryAnalyticsClient()
    ) {
        self.queueService = queueService
        self.timerEngine = timerEngine
        self.rewardEngine = rewardEngine
        self.analytics = analytics
    }

    func configure(modelContext: ModelContext) async {
        if taskRepository == nil {
            taskRepository = TaskRepository(
                context: modelContext,
                queueService: queueService,
                timerEngine: timerEngine,
                rewardEngine: rewardEngine,
                analytics: analytics
            )
        }
        guard !didBootstrap else {
            await refreshXP()
            return
        }
        do {
            try await taskRepository?.bootstrapFromStore()
            didBootstrap = true
        } catch {
            didBootstrap = true
        }
        await refreshXP()
    }

    func refreshXP() async {
        let xp = await rewardEngine.totalXP()
        totalXP = xp
        levelName = LevelTable.level(forXP: xp).name
    }

    /// Brief post-completion undo affordance (skippable, auto-dismisses).
    func offerUndo(forTaskTitle title: String, seconds: TimeInterval = 8) {
        undoClearTask?.cancel()
        undoBannerTitle = title
        undoClearTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.undoBannerTitle = nil
            }
        }
    }

    func clearUndoBanner() {
        undoClearTask?.cancel()
        undoBannerTitle = nil
    }
}
