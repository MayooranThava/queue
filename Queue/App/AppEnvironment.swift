import SwiftUI
import SwiftData
import QueueCore
#if canImport(WidgetKit)
import WidgetKit
#endif

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
    /// Live focus snapshot for Queue chrome (timer stays visible outside Focus).
    @Published private(set) var focusSnapshot: FocusWidgetSnapshot?
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
            await refreshFocusSnapshot()
            return
        }
        do {
            try await taskRepository?.bootstrapFromStore()
            didBootstrap = true
        } catch {
            didBootstrap = true
        }
        await refreshXP()
        await refreshFocusSnapshot()
    }

    func refreshXP() async {
        let xp = await rewardEngine.totalXP()
        totalXP = xp
        levelName = LevelTable.level(forXP: xp).name
    }

    /// Pulls the authoritative session and reloads Home Screen widgets.
    func refreshFocusSnapshot() async {
        let snapshot = await taskRepository?.currentFocusSnapshot()
        focusSnapshot = snapshot
        reloadWidgets()
        await FocusLiveActivityController.shared.sync(snapshot: snapshot)
    }

    func reloadWidgets() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
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
