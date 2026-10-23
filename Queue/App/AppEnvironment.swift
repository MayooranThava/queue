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
    /// Live focus snapshot for Queue chrome (timer stays visible outside Focus).
    @Published private(set) var focusSnapshot: FocusWidgetSnapshot?
    /// Set when a widget, Live Activity, or focus-end alert asks to jump into focus.
    @Published var pendingOpenFocus = false
    /// Task named by a focus-end alert. Nil means "open the current focus block."
    @Published var pendingFocusTaskID: UUID?
    let focusAlertCenter: SystemFocusEndNotificationScheduler
    private var undoClearTask: Task<Void, Never>?
    private var didBootstrap = false
    private var lastSeenStoreGeneration = 0
    private var storeObserver: WidgetStoreChangeObserver?

    init(
        queueService: TaskQueueService = TaskQueueService(),
        timerEngine: FocusTimerEngine = FocusTimerEngine(),
        rewardEngine: RewardEngine = RewardEngine(),
        analytics: AnalyticsClient = InMemoryAnalyticsClient(),
        focusAlertCenter: SystemFocusEndNotificationScheduler = .shared
    ) {
        self.queueService = queueService
        self.timerEngine = timerEngine
        self.rewardEngine = rewardEngine
        self.analytics = analytics
        self.focusAlertCenter = focusAlertCenter
        focusAlertCenter.setOpenTaskHandler { [weak self] taskID in
            Task { @MainActor in
                self?.openFocus(taskID: taskID)
            }
        }
        focusAlertCenter.install()
        storeObserver = WidgetStoreChangeObserver { [weak self] in
            Task { @MainActor in
                await self?.importWidgetEditsIfNeeded()
                await self?.refreshFocusSnapshot()
            }
        }
        storeObserver?.start()
    }

    func openFocus(taskID: UUID?) {
        pendingFocusTaskID = taskID
        pendingOpenFocus = true
    }

    func configure(modelContext: ModelContext) async {
        if taskRepository == nil {
            taskRepository = TaskRepository(
                context: modelContext,
                queueService: queueService,
                timerEngine: timerEngine,
                rewardEngine: rewardEngine,
                analytics: analytics,
                focusNotifications: focusAlertCenter,
                notificationAuthorizer: focusAlertCenter
            )
        }
        guard !didBootstrap else {
            await importWidgetEditsIfNeeded()
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
        lastSeenStoreGeneration = WidgetStoreGeneration.current()
        await refreshXP()
        await refreshFocusSnapshot()
    }

    /// Reloads SwiftData after a widget button wrote the shared store.
    func importWidgetEditsIfNeeded() async {
        guard taskRepository != nil else { return }
        let generation = WidgetStoreGeneration.current()
        guard generation != lastSeenStoreGeneration else { return }
        do {
            let dump = try SharedStoreDump.load()
            try await taskRepository?.applyExternalSnapshot(
                tasks: dump.tasks,
                session: dump.session,
                transactions: dump.transactions
            )
            lastSeenStoreGeneration = WidgetStoreGeneration.current()
            focusSnapshot = await taskRepository?.currentFocusSnapshot()
            await refreshXP()
            await FocusLiveActivityController.shared.sync(snapshot: focusSnapshot)
        } catch {
            // Leave the generation unseen so the next foreground can retry.
        }
    }

    func refreshXP() async {
        let xp = await rewardEngine.totalXP()
        totalXP = xp
        levelName = LevelTable.level(forXP: xp).name
    }

    /// Pulls the authoritative session and reloads Home Screen widgets.
    func refreshFocusSnapshot() async {
        if WidgetStoreGeneration.current() != lastSeenStoreGeneration {
            await importWidgetEditsIfNeeded()
        }
        // A failed import must not overwrite the widget's snapshot with stale memory.
        guard WidgetStoreGeneration.current() == lastSeenStoreGeneration else { return }
        let snapshot = await taskRepository?.currentFocusSnapshot()
        await taskRepository?.publishQueueSnapshot()
        focusSnapshot = snapshot
        reloadWidgets()
        await FocusLiveActivityController.shared.sync(snapshot: snapshot)
    }

    func reloadWidgets() {
        QueueWidgetReload.reload()
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
