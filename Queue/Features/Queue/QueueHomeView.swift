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
        .task {
            await services.configure(modelContext: modelContext)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await services.refreshFocusSnapshot() }
            }
        }
        .onChange(of: services.pendingOpenFocus) { _, shouldOpen in
            guard shouldOpen else { return }
            openFocusFromDeepLink()
        }
        .safeAreaInset(edge: .bottom) {
            if let undoTitle = services.undoBannerTitle {
                undoBanner(title: undoTitle)
            }
        }
    }

    private func openFocusFromDeepLink() {
        defer { services.pendingOpenFocus = false }
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
                .foregroundStyle(QueueColors.primaryText)
            Text("Add one small task. Focus on that alone.")
                .font(QueueTypography.body())
                .foregroundStyle(QueueColors.secondaryText)
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
        ScrollView {
            LazyVStack(spacing: queuePresentationMode == "list" ? QueueSpacing.sm : 0) {
                HStack {
                    Text("\(activeTasks.count) tasks · ~\(remainingWorkMinutes) min")
                        .font(QueueTypography.caption())
                        .foregroundStyle(QueueColors.secondaryText)
                    Spacer()
                    Picker("Queue view", selection: $queuePresentationMode) {
                        Text("Stack").tag("stack")
                        Text("List").tag("list")
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 180)
                    .accessibilityLabel("Queue presentation")
                }
                .padding(.horizontal, QueueSpacing.md)
                .padding(.vertical, QueueSpacing.sm)
                ForEach(Array(activeTasks.enumerated()), id: \.element.id) { index, task in
                    let isHead = index == 0
                    Group {
                        if isHead {
                            ActiveTaskStackBlock(
                                task: task,
                                focusSnapshot: matchingSnapshot(for: task),
                                blockIndex: index,
                                onEdit: { editingTask = task },
                                onFocus: { focusTask = task }
                            )
                        } else {
                            UpcomingTaskStackBlock(
                                task: task,
                                showStartTime: showPlannedStartTimes,
                                startTime: projectedStarts[task.id],
                                blockIndex: index,
                                canMoveUp: index > 1,
                                canMoveDown: index < activeTasks.count - 1,
                                onTap: { editingTask = task },
                                onMoveUp: { moveTask(id: task.id, direction: -1) },
                                onMoveDown: { moveTask(id: task.id, direction: 1) }
                            )
                        }
                    }
                    .id(task.id)
                    .frame(maxWidth: .infinity, minHeight: isHead ? 300 : (queuePresentationMode == "list" ? 112 : 168), alignment: .topLeading)
                    .scrollTransition(
                        topLeading: (reduceMotion || queuePresentationMode == "list") ? .identity : .animated(QueueMotion.stackScroll),
                        bottomTrailing: (reduceMotion || queuePresentationMode == "list") ? .identity : .animated(QueueMotion.stackScroll)
                    ) { content, phase in
                        content
                            .opacity(queuePresentationMode == "list" ? 1 : stackOpacity(for: phase))
                            .scaleEffect(x: 1, y: queuePresentationMode == "list" ? 1 : stackScale(for: phase), anchor: .top)
                            .offset(y: queuePresentationMode == "list" ? 0 : stackOffset(for: phase))
                    }
                }
            }
            .scrollTargetLayout()
        }
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.viewAligned)
        .background(QueueColors.background)
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
                .foregroundStyle(QueueColors.primaryText)
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

private struct ActiveTaskStackBlock: View {
    let task: QueueTask
    let focusSnapshot: FocusWidgetSnapshot?
    let blockIndex: Int
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
                .foregroundStyle(QueueColors.secondaryText)
                .tracking(1.2)

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: QueueSpacing.xs) {
                    Text(task.title)
                        .font(QueueTypography.title(28))
                        .foregroundStyle(QueueColors.primaryText)
                        .lineLimit(3)
                        .minimumScaleFactor(0.78)
                        .accessibilityAddTraits(.isHeader)

                    if focusSnapshot == nil {
                        Text("\(durationLabel(task.estimatedDuration)) · \(task.difficulty.displayName)")
                            .font(QueueTypography.body())
                            .foregroundStyle(QueueColors.secondaryText)
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
                    .foregroundStyle(QueueColors.sageDeep)
                    .accessibilityHidden(true)
            }

            if let notes = task.notes, !notes.isEmpty {
                Text(notes)
                    .font(QueueTypography.body(15))
                    .foregroundStyle(QueueColors.secondaryText)
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
                .foregroundStyle(QueueColors.sageDeep)
                .accessibilityHint("Opens the editor for the active task")
        }
        .padding(.horizontal, QueueSpacing.lg)
        .padding(.vertical, QueueSpacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(QueueColors.stackBlock(index: blockIndex))
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
                    .foregroundStyle(QueueColors.primaryText)
                    .contentTransition(.numericText())
                    .accessibilityLabel("Time remaining \(FocusTimerFormatting.spoken(remaining))")

                Text(statusCaption(for: snapshot))
                    .font(QueueTypography.caption())
                    .foregroundStyle(QueueColors.secondaryText)
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
    let canMoveUp: Bool
    let canMoveDown: Bool
    var onTap: () -> Void
    var onMoveUp: () -> Void
    var onMoveDown: () -> Void

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: QueueSpacing.md) {
                VStack(alignment: .leading, spacing: QueueSpacing.xs) {
                    Text(task.title.uppercased())
                        .font(QueueTypography.title(26))
                        .foregroundStyle(QueueColors.primaryText)
                        .lineLimit(3)
                        .minimumScaleFactor(0.8)
                        .multilineTextAlignment(.leading)

                    Text(subtitle)
                        .font(QueueTypography.body(15))
                        .foregroundStyle(QueueColors.secondaryText)
                }
                Spacer(minLength: QueueSpacing.sm)
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(QueueColors.secondaryText.opacity(0.7))
                    .padding(.top, 6)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, QueueSpacing.lg)
            .padding(.vertical, QueueSpacing.xl)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(QueueColors.stackBlock(index: blockIndex))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(task.title), \(subtitle)")
        .accessibilityHint("Double tap to edit. Use the context menu to reorder.")
        .contextMenu {
            Button("Edit") { onTap() }
            if canMoveUp {
                Button {
                    onMoveUp()
                } label: {
                    Label("Move up", systemImage: "arrow.up")
                }
            }
            if canMoveDown {
                Button {
                    onMoveDown()
                } label: {
                    Label("Move down", systemImage: "arrow.down")
                }
            }
        }
    }

    private var subtitle: String {
        if showStartTime, let startTime {
            let prefix = task.plannedStartAt != nil ? "Starts" : "About"
            return "\(prefix) \(Self.timeFormatter.string(from: startTime)) · \(task.difficulty.displayName)"
        }
        return "\(max(1, Int(task.estimatedDuration / 60))) min · \(task.difficulty.displayName)"
    }
}
