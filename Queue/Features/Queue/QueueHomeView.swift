import SwiftUI
import SwiftData
import QueueCore

struct QueueHomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var services: AppServices
    @Query(sort: [
        SortDescriptor(\TaskEntity.queuePosition),
        SortDescriptor(\TaskEntity.createdAt)
    ]) private var taskEntities: [TaskEntity]

    @AppStorage("showPlannedStartTimes") private var showPlannedStartTimes = false
    @AppStorage("queuePresentationMode") private var queuePresentationMode = "stack"

    @State private var showAddTask = false
    @State private var editingTask: QueueTask?
    @State private var focusTask: QueueTask?
    @State private var errorMessage: String?
    @State private var pendingQueueAction: PendingQueueAction?
    @State private var queueActionInFlight = false

    private var activeTasks: [QueueTask] {
        taskEntities
            .map { $0.asDomain() }
            .filter(\.isInActiveQueue)
            .sorted { $0.queuePosition < $1.queuePosition }
    }

    private var headTask: QueueTask? { activeTasks.first }

    private var remainingWorkMinutes: Int {
        Int(ceil(activeTasks.reduce(0.0) { $0 + $1.estimatedDuration } / 60.0))
    }

    private var projectedStarts: [UUID: Date] {
        QueueSchedule.projectedStarts(orderedActiveTasks: activeTasks, from: Date())
    }

    var body: some View {
        ZStack {
            QueueColors.background.ignoresSafeArea()

            Group {
                if activeTasks.isEmpty {
                    emptyState
                } else {
                    populatedState
                }
            }
        }
        .navigationTitle("Queue")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if activeTasks.count > 1 {
                    Toggle(isOn: $showPlannedStartTimes) {
                        Image(systemName: showPlannedStartTimes ? "clock" : "timer")
                    }
                    .toggleStyle(.button)
                    .accessibilityLabel(
                        showPlannedStartTimes
                            ? "Showing start times. Switch to durations."
                            : "Showing durations. Switch to start times."
                    )
                }
                Button {
                    showAddTask = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: QueueSpacing.minTouch, height: QueueSpacing.minTouch)
                }
                .accessibilityLabel("Add task")
            }
        }
        .sheet(isPresented: $showAddTask) {
            AddEditTaskView { draft in
                await createTask(draft)
            }
        }
        .sheet(item: $editingTask) { task in
            AddEditTaskView(existing: task) { draft in
                await updateTask(task, draft: draft)
            }
        }
        .fullScreenCover(item: $focusTask, onDismiss: {
            Task { await services.refreshFocusSnapshot() }
        }) { task in
            FocusSessionView(task: task)
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .confirmationDialog(
            pendingQueueAction?.title ?? "Task",
            isPresented: Binding(
                get: { pendingQueueAction != nil },
                set: { if !$0 { pendingQueueAction = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingQueueAction
        ) { action in
            Button(action.confirmButtonTitle, role: action.kind == .delete ? .destructive : nil) {
                Task { await perform(action) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { action in
            Text(action.message)
        }
        .task {
            await services.configure(modelContext: modelContext)
            openFocusFromDeepLinkIfNeeded()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task {
                    await services.importWidgetEditsIfNeeded()
                    await services.refreshFocusSnapshot()
                }
            }
        }
        .onAppear {
            openFocusFromDeepLinkIfNeeded()
        }
        .onChange(of: services.pendingOpenFocus) { _, shouldOpen in
            guard shouldOpen else { return }
            openFocusFromDeepLinkIfNeeded()
        }
        .onChange(of: taskEntities.count) { _, _ in
            openFocusFromDeepLinkIfNeeded()
        }
        .safeAreaInset(edge: .bottom) {
            if let undoTitle = services.undoBannerTitle {
                undoBanner(title: undoTitle)
            }
        }
    }

    private func openFocusFromDeepLinkIfNeeded() {
        guard services.pendingOpenFocus else { return }
        if let requestedTaskID = services.pendingFocusTaskID {
            // A cold launch from the alert can arrive before SwiftData publishes rows.
            guard !taskEntities.isEmpty else { return }
            services.pendingOpenFocus = false
            services.pendingFocusTaskID = nil
            if let match = activeTasks.first(where: { $0.id == requestedTaskID }) {
                focusTask = match
            }
            return
        }
        services.pendingOpenFocus = false
        guard let headTask else { return }
        focusTask = headTask
    }

    private var emptyState: some View {
        VStack(spacing: QueueSpacing.lg) {
            Spacer()
            CompanionAnimationView(state: .idle, reduceMotion: false)
                .frame(height: 140)
                .accessibilityHidden(true)
            Text("Nothing in your queue")
                .font(QueueTypography.title(28))
                .foregroundStyle(QueueColors.textPrimary)
            Text("Add one small task. Focus on that alone.")
                .font(QueueTypography.body())
                .foregroundStyle(QueueColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, QueueSpacing.xl)
            Button("Add your first task") {
                showAddTask = true
            }
            .buttonStyle(QueuePrimaryButtonStyle())
            .padding(.horizontal, QueueSpacing.xl)
            Spacer()
        }
        .accessibilityElement(children: .contain)
    }

    private var populatedState: some View {
        Group {
            if queuePresentationMode == "list" {
                listQueue
            } else {
                stackQueue
            }
        }
    }

    private var queueSummaryHeader: some View {
        HStack {
            Text("\(activeTasks.count) tasks · ~\(remainingWorkMinutes) min")
                .font(QueueTypography.caption())
                .foregroundStyle(QueueColors.textSecondary)
            Spacer()
            Picker("Queue view", selection: $queuePresentationMode) {
                Text("Stack").tag("stack")
                Text("List").tag("list")
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 180)
            .accessibilityLabel("Queue presentation")
        }
    }

    /// List mode uses row swipes. Stack mode keeps the vertical snap scroll, so actions live in the context menu.
    private var listQueue: some View {
        List {
            queueSummaryHeader
                .listRowInsets(EdgeInsets(
                    top: QueueSpacing.sm,
                    leading: QueueSpacing.md,
                    bottom: QueueSpacing.sm,
                    trailing: QueueSpacing.md
                ))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            ForEach(Array(activeTasks.enumerated()), id: \.element.id) { index, task in
                taskBlock(index: index, task: task)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: QueueSpacing.sm, trailing: 0))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            requestDelete(task)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        Button {
                            requestSkip(task)
                        } label: {
                            Label("Skip", systemImage: "forward.end")
                        }
                        .tint(QueueColors.fixed(.primary, style: .light))
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                        if canMoveToBottom(index: index) {
                            Button {
                                requestMoveToBottom(task)
                            } label: {
                                Label("Move to bottom", systemImage: "arrow.down.to.line")
                            }
                            .tint(QueueColors.fixed(.success, style: .light))
                        }
                    }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(QueueColors.background)
        .environment(\.defaultMinListRowHeight, 1)
    }

    private var stackQueue: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                queueSummaryHeader
                    .padding(.horizontal, QueueSpacing.md)
                    .padding(.vertical, QueueSpacing.sm)
                ForEach(Array(activeTasks.enumerated()), id: \.element.id) { index, task in
                    taskBlock(index: index, task: task)
                        .scrollTransition(
                            topLeading: reduceMotion ? .identity : .animated(QueueMotion.stackScroll),
                            bottomTrailing: reduceMotion ? .identity : .animated(QueueMotion.stackScroll)
                        ) { content, phase in
                            content
                                .opacity(stackOpacity(for: phase))
                                .scaleEffect(x: 1, y: stackScale(for: phase), anchor: .top)
                                .offset(y: stackOffset(for: phase))
                        }
                }
            }
            .scrollTargetLayout()
        }
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.viewAligned)
        .background(QueueColors.background)
    }

    private func taskBlock(index: Int, task: QueueTask) -> some View {
        let isHead = index == 0
        let listMode = queuePresentationMode == "list"
        let menu = QueueBlockMenu(
            onEdit: { editingTask = task },
            onMoveUp: index > 1 ? { moveTask(id: task.id, direction: -1) } : nil,
            onMoveDown: (index > 0 && index < activeTasks.count - 1) ? { moveTask(id: task.id, direction: 1) } : nil,
            onMoveToBottom: canMoveToBottom(index: index) ? { requestMoveToBottom(task) } : nil,
            onSkip: { requestSkip(task) },
            onDelete: { requestDelete(task) }
        )
        return Group {
            if isHead {
                ActiveTaskStackBlock(
                    task: task,
                    focusSnapshot: matchingSnapshot(for: task),
                    blockIndex: index,
                    menu: menu,
                    onEdit: { editingTask = task },
                    onFocus: { focusTask = task }
                )
            } else {
                UpcomingTaskStackBlock(
                    task: task,
                    showStartTime: showPlannedStartTimes,
                    startTime: projectedStarts[task.id],
                    blockIndex: index,
                    listMode: listMode,
                    menu: menu,
                    onTap: { editingTask = task }
                )
            }
        }
        .id(task.id)
        .frame(
            maxWidth: .infinity,
            minHeight: isHead ? 300 : (listMode ? 112 : 168),
            alignment: .topLeading
        )
        .accessibilityAction(named: Text("Skip")) { requestSkip(task) }
        .accessibilityAction(named: Text("Delete")) { requestDelete(task) }
        .modifier(MoveToBottomAccessibilityAction(enabled: canMoveToBottom(index: index)) {
            requestMoveToBottom(task)
        })
    }

    private func stackOpacity(for phase: ScrollTransitionPhase) -> Double {
        if reduceMotion || phase.isIdentity { return 1 }
        return 0.58 + (0.42 * (1 - abs(phase.value)))
    }

    private func stackScale(for phase: ScrollTransitionPhase) -> CGFloat {
        if reduceMotion || phase.isIdentity { return 1 }
        // Compress toward the top edge so blocks read as a physical stack while scrolling.
        return 0.88 + (0.12 * (1 - abs(phase.value)))
    }

    private func stackOffset(for phase: ScrollTransitionPhase) -> CGFloat {
        if reduceMotion || phase.isIdentity { return 0 }
        return phase.value * -22
    }

    private func matchingSnapshot(for task: QueueTask) -> FocusWidgetSnapshot? {
        guard let snapshot = services.focusSnapshot,
              snapshot.taskID == task.id,
              snapshot.isActivelyTiming
        else { return nil }
        return snapshot
    }

    private func undoBanner(title: String) -> some View {
        HStack {
            Text("Completed “\(title)”")
                .font(QueueTypography.body(15))
                .foregroundStyle(QueueColors.textPrimary)
            Spacer()
            Button("Undo") {
                Task { await undoCompletion() }
            }
            .font(QueueTypography.headline(15))
        }
        .padding(QueueSpacing.md)
        .background(.ultraThinMaterial)
        .padding(.horizontal, QueueSpacing.md)
        .padding(.bottom, QueueSpacing.sm)
    }

    private func createTask(_ draft: TaskDraft) async {
        do {
            _ = try await services.taskRepository?.create(
                title: draft.title,
                notes: draft.notes,
                estimatedDuration: draft.estimatedDuration,
                difficulty: draft.difficulty,
                plannedStartAt: draft.plannedStartAt
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func updateTask(_ task: QueueTask, draft: TaskDraft) async {
        var copy = task
        copy.title = draft.title
        copy.notes = draft.notes
        copy.estimatedDuration = draft.estimatedDuration
        copy.difficulty = draft.difficulty
        copy.plannedStartAt = draft.plannedStartAt
        do {
            try await services.taskRepository?.update(copy)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func canMoveToBottom(index: Int) -> Bool {
        activeTasks.count > 1 && index < activeTasks.count - 1
    }

    private func requestDelete(_ task: QueueTask) {
        Task { await presentOrPerform(.delete, task: task, alwaysConfirm: true) }
    }

    private func requestSkip(_ task: QueueTask) {
        Task { await presentOrPerform(.skip, task: task, alwaysConfirm: false) }
    }

    private func requestMoveToBottom(_ task: QueueTask) {
        guard let index = activeTasks.firstIndex(where: { $0.id == task.id }),
              canMoveToBottom(index: index) else { return }
        Task { await presentOrPerform(.moveToBottom, task: task, alwaysConfirm: false) }
    }

    /// Delete always confirms. Skip and move-to-bottom confirm only when they would end focus.
    private func presentOrPerform(
        _ kind: PendingQueueAction.Kind,
        task: QueueTask,
        alwaysConfirm: Bool
    ) async {
        guard pendingQueueAction == nil, !queueActionInFlight else { return }
        let sessionLive = await services.taskRepository?.hasLiveFocusSession(for: task.id) ?? false
        let endsFocus = ActiveTaskEditPolicy.mustAcknowledgeFocusEnd(
            status: task.status,
            hasLiveSession: sessionLive
        )
        let request = PendingQueueAction(kind: kind, task: task, endsFocus: endsFocus)
        if alwaysConfirm || endsFocus {
            pendingQueueAction = request
        } else {
            await perform(request)
        }
    }

    private func perform(_ action: PendingQueueAction) async {
        guard !queueActionInFlight else { return }
        queueActionInFlight = true
        defer { queueActionInFlight = false }
        guard let repository = services.taskRepository else {
            errorMessage = "Queue isn't ready yet."
            return
        }
        do {
            switch action.kind {
            case .delete:
                try await repository.delete(id: action.taskID, endFocus: action.endsFocus)
            case .skip:
                _ = try await repository.skip(id: action.taskID, endFocus: action.endsFocus)
            case .moveToBottom:
                _ = try await repository.requeue(id: action.taskID, endFocus: action.endsFocus)
            }
            await services.refreshFocusSnapshot()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Moves an upcoming task within the active queue (head stays at index 0).
    private func moveTask(id: UUID, direction: Int) {
        guard let index = activeTasks.firstIndex(where: { $0.id == id }), index > 0 else { return }
        let destination = index + direction
        guard destination >= 1, destination < activeTasks.count else { return }
        var ordered = activeTasks
        ordered.swapAt(index, destination)
        Task {
            do {
                try await services.taskRepository?.reorder(orderedIDs: ordered.map(\.id))
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func undoCompletion() async {
        do {
            _ = try await services.taskRepository?.undoLastCompletion()
            services.clearUndoBanner()
            await services.refreshXP()
            await services.refreshFocusSnapshot()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Stack blocks

private struct QueueBlockMenu {
    var onEdit: () -> Void
    var onMoveUp: (() -> Void)?
    var onMoveDown: (() -> Void)?
    var onMoveToBottom: (() -> Void)?
    var onSkip: () -> Void
    var onDelete: () -> Void
}

private struct QueueBlockInteractions: ViewModifier {
    let menu: QueueBlockMenu

    func body(content: Content) -> some View {
        content.contextMenu {
            Button(action: menu.onEdit) {
                Label("Edit", systemImage: "pencil")
            }
            if let onMoveUp = menu.onMoveUp {
                Button(action: onMoveUp) {
                    Label("Move up", systemImage: "arrow.up")
                }
            }
            if let onMoveDown = menu.onMoveDown {
                Button(action: onMoveDown) {
                    Label("Move down", systemImage: "arrow.down")
                }
            }
            if let onMoveToBottom = menu.onMoveToBottom {
                Button(action: onMoveToBottom) {
                    Label("Move to bottom", systemImage: "arrow.down.to.line")
                }
            }
            Button(action: menu.onSkip) {
                Label("Skip", systemImage: "forward.end")
            }
            Button(role: .destructive, action: menu.onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

private struct ActiveTaskStackBlock: View {
    let task: QueueTask
    let focusSnapshot: FocusWidgetSnapshot?
    let blockIndex: Int
    let menu: QueueBlockMenu
    var onEdit: () -> Void
    var onFocus: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isAlreadyFocusing: Bool {
        focusSnapshot != nil
            || task.status == .active
            || task.status == .paused
            || task.status == .expired
    }

    private var companionState: CompanionVisualState {
        guard let focusSnapshot else {
            return isAlreadyFocusing ? .working : .idle
        }
        switch focusSnapshot.session.state {
        case .running: return .working
        case .paused: return .paused
        case .expired: return .timerExpired
        default: return .working
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: QueueSpacing.md) {
            Text("NOW")
                .font(QueueTypography.caption())
                .foregroundStyle(QueueColors.textSecondary)
                .tracking(1.2)

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: QueueSpacing.xs) {
                    Text(task.title)
                        .font(QueueTypography.title(28))
                        .foregroundStyle(QueueColors.textPrimary)
                        .lineLimit(3)
                        .minimumScaleFactor(0.78)
                        .accessibilityAddTraits(.isHeader)

                    if focusSnapshot == nil {
                        Text("\(durationLabel(task.estimatedDuration)) · \(task.difficulty.displayName)")
                            .font(QueueTypography.body())
                            .foregroundStyle(QueueColors.textSecondary)
                    }
                }
                Spacer(minLength: QueueSpacing.sm)
                companionBadge
            }

            if let focusSnapshot {
                liveTimer(snapshot: focusSnapshot)
            }

            if focusSnapshot != nil {
                Label(focusBadgeTitle(for: focusSnapshot), systemImage: "leaf.fill")
                    .font(QueueTypography.caption())
                    .foregroundStyle(QueueColors.success)
                    .accessibilityHidden(true)
            }

            if let notes = task.notes, !notes.isEmpty {
                Text(notes)
                    .font(QueueTypography.body(15))
                    .foregroundStyle(QueueColors.textSecondary)
            }

            Spacer(minLength: 0)

            Button(isAlreadyFocusing ? "Continue focus" : "Start focus", action: onFocus)
                .buttonStyle(QueuePrimaryButtonStyle())
                .accessibilityHint(
                    isAlreadyFocusing
                        ? "Returns to the running focus session"
                        : "Starts the countdown and working animation immediately"
                )

            Button("Edit task", action: onEdit)
                .font(QueueTypography.caption())
                .foregroundStyle(QueueColors.primary)
                .accessibilityHint("Opens the editor for the active task")
        }
        .padding(.horizontal, QueueSpacing.lg)
        .padding(.vertical, QueueSpacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(QueueColors.stackBlock(index: blockIndex))
        .contentShape(Rectangle())
        .modifier(QueueBlockInteractions(menu: menu))
        .accessibilityElement(children: .contain)
    }

    private var companionBadge: some View {
        ZStack {
            if let focusSnapshot {
                TimelineView(.periodic(from: .now, by: reduceMotion ? 1 : 0.5)) { context in
                    FocusCountdownRing(
                        progress: focusSnapshot.progress(at: context.date),
                        isExpired: focusSnapshot.session.state == .expired,
                        isPaused: focusSnapshot.session.state == .paused,
                        reduceMotion: reduceMotion
                    )
                    .frame(width: 76, height: 76)
                }
            }
            CompanionAnimationView(
                state: companionState,
                reduceMotion: false,
                compact: true
            )
            .frame(width: 64, height: 64)
        }
        .frame(width: 80, height: 80)
        .accessibilityHidden(true)
    }

    private func liveTimer(snapshot: FocusWidgetSnapshot) -> some View {
        TimelineView(.periodic(from: .now, by: reduceMotion ? 1 : 0.25)) { context in
            let remaining = snapshot.remaining(at: context.date)
            VStack(alignment: .leading, spacing: 4) {
                Text(FocusTimerFormatting.clock(remaining))
                    .font(QueueTypography.monoTimer(34))
                    .foregroundStyle(QueueColors.textPrimary)
                    .contentTransition(.numericText())
                    .accessibilityLabel("Time remaining \(FocusTimerFormatting.spoken(remaining))")

                Text(statusCaption(for: snapshot))
                    .font(QueueTypography.caption())
                    .foregroundStyle(QueueColors.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func statusCaption(for snapshot: FocusWidgetSnapshot) -> String {
        switch snapshot.session.state {
        case .paused:
            return "Paused · \(snapshot.difficultyDisplayName)"
        case .expired:
            return "Time’s up · finish when you’re ready"
        case .running:
            return "Focusing · \(snapshot.difficultyDisplayName) · \(durationLabel(snapshot.estimatedDuration))"
        default:
            return "\(durationLabel(task.estimatedDuration)) · \(task.difficulty.displayName)"
        }
    }

    private func durationLabel(_ interval: TimeInterval) -> String {
        let minutes = max(1, Int(interval / 60))
        return "\(minutes) min estimate"
    }

    private func focusBadgeTitle(for snapshot: FocusWidgetSnapshot?) -> String {
        switch snapshot?.session.state {
        case .paused: return "Paused — timer keeps your place"
        case .expired: return "Over estimate — finish when ready"
        default: return "Timer stays on Queue and Home Screen"
        }
    }
}

private struct UpcomingTaskStackBlock: View {
    let task: QueueTask
    let showStartTime: Bool
    let startTime: Date?
    let blockIndex: Int
    let listMode: Bool
    let menu: QueueBlockMenu
    var onTap: () -> Void

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        HStack(alignment: .top, spacing: QueueSpacing.md) {
            VStack(alignment: .leading, spacing: QueueSpacing.xs) {
                Text(task.title.uppercased())
                    .font(QueueTypography.title(26))
                    .foregroundStyle(QueueColors.textPrimary)
                    .lineLimit(3)
                    .minimumScaleFactor(0.8)
                    .multilineTextAlignment(.leading)

                Text(subtitle)
                    .font(QueueTypography.body(15))
                    .foregroundStyle(QueueColors.textSecondary)
            }
            Spacer(minLength: QueueSpacing.sm)
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(QueueColors.textSecondary)
                .padding(.top, 6)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, QueueSpacing.lg)
        .padding(.vertical, QueueSpacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(QueueColors.stackBlock(index: blockIndex))
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .modifier(QueueBlockInteractions(menu: menu))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("\(task.title), \(subtitle)")
        .accessibilityHint(
            listMode
                ? "Double tap to edit. Swipe to skip, move to the bottom, or delete."
                : "Double tap to edit. Long press to reorder, skip, or delete."
        )
        .accessibilityAction(.default) { onTap() }
    }

    private var subtitle: String {
        if showStartTime, let startTime {
            let prefix = task.plannedStartAt != nil ? "Starts" : "About"
            return "\(prefix) \(Self.timeFormatter.string(from: startTime)) · \(task.difficulty.displayName)"
        }
        return "\(max(1, Int(task.estimatedDuration / 60))) min · \(task.difficulty.displayName)"
    }
}

private struct PendingQueueAction: Identifiable {
    enum Kind {
        case delete
        case skip
        case moveToBottom
    }

    let id = UUID()
    let taskID: UUID
    let kind: Kind
    let endsFocus: Bool
    let title: String
    let message: String

    init(kind: Kind, task: QueueTask, endsFocus: Bool) {
        self.taskID = task.id
        self.kind = kind
        self.endsFocus = endsFocus
        switch kind {
        case .delete:
            title = "Delete this task?"
            message = endsFocus
                ? "This ends focus on “\(task.title)” and removes it from your queue. Nothing else starts on its own."
                : "“\(task.title)” will leave your queue."
        case .skip:
            title = "Skip this task?"
            message = "This ends focus on “\(task.title)” and removes it from your queue. Nothing else starts on its own."
        case .moveToBottom:
            title = "Move this task to the bottom?"
            message = "This ends focus on “\(task.title)” and places it at the bottom of your queue. Nothing else starts on its own."
        }
    }

    var confirmButtonTitle: String {
        switch kind {
        case .delete: return "Delete"
        case .skip: return "Skip"
        case .moveToBottom: return "Move to bottom"
        }
    }
}

private struct MoveToBottomAccessibilityAction: ViewModifier {
    let enabled: Bool
    let action: () -> Void

    func body(content: Content) -> some View {
        if enabled {
            content.accessibilityAction(named: Text("Move to bottom")) { action() }
        } else {
            content
        }
    }
}
