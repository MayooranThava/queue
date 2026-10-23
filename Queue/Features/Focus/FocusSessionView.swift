import SwiftUI
import SwiftData
import QueueCore

/// Immersive Focus: Start immediately begins a timestamp-backed countdown
/// with a working companion. Remaining time is derived, never tick-decremented.
struct FocusSessionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.queueCompanionVisible) private var companionVisible
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var services: AppServices

    @State private var currentTask: QueueTask
    @State private var session: FocusSession?
    @State private var companionState: CompanionVisualState = .preparing
    @State private var errorMessage: String?
    @State private var completionOutcome: FocusCompletionOutcome?
    @State private var nextOffer: NextBlockOffer?
    @State private var autoStartStartedAt: Date?
    @State private var autoStartCancelled = false
    @State private var breakStartedAt: Date?
    @State private var didBootstrap = false
    @State private var contentAppeared = false
    @State private var focusAlertsDenied = false
    @State private var handoffLocked = false

    init(task: QueueTask) {
        _currentTask = State(initialValue: task)
    }

    var body: some View {
        ZStack {
            QueueColors.background.ignoresSafeArea()

            if let breakStartedAt, let next = nextOffer?.task {
                FocusBreakView(
                    nextTask: next,
                    startedAt: breakStartedAt,
                    duration: nextOffer?.breakDuration ?? NextBlockPlanner.breakDuration,
                    onSkip: skipBreak,
                    onElapsed: breakElapsed,
                    onLeave: leaveBreak
                )
                .transition(.opacity)
            } else if let completionOutcome {
                CompletionCelebrationView(
                    outcome: completionOutcome,
                    offer: nextOffer,
                    autoStartStartedAt: autoStartCancelled ? nil : autoStartStartedAt,
                    onContinue: { finishAfterCelebration(outcome: completionOutcome) },
                    onSkip: { finishAfterCelebration(outcome: completionOutcome) },
                    onStartNext: {
                        guard let next = nextOffer?.task else { return }
                        Task { await startNext(next) }
                    },
                    onTakeBreak: takeBreak,
                    onCancelAutoStart: cancelAutoStart,
                    onAutoStartElapsed: autoStartElapsed
                )
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else {
                focusContent
                    .opacity(contentAppeared ? 1 : 0)
                    .offset(y: contentAppeared ? 0 : 12)
            }
        }
        .preferredColorScheme(.dark)
        .task {
            await bootstrapFocus()
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {
                if completionOutcome == nil {
                    dismiss()
                }
            }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var focusContent: some View {
        VStack(spacing: QueueSpacing.lg) {
            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(QueueColors.textSecondary)
                        .frame(width: QueueSpacing.minTouch, height: QueueSpacing.minTouch)
                }
                .accessibilityLabel("Close focus")
            }
            .padding(.horizontal, QueueSpacing.md)

            Spacer(minLength: QueueSpacing.sm)

            Text(currentTask.title)
                .font(QueueTypography.title(22))
                .foregroundStyle(QueueColors.textPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, QueueSpacing.xl)
                .accessibilityAddTraits(.isHeader)

            TimelineView(.periodic(from: .now, by: reduceMotion ? 1 : 0.25)) { context in
                let remaining = displayedRemaining(at: context.date)
                let progress = ringProgress(at: context.date)
                VStack(spacing: QueueSpacing.md) {
                    ZStack {
                        FocusCountdownRing(
                            progress: progress,
                            isExpired: session?.state == .expired,
                            isPaused: session?.state == .paused,
                            reduceMotion: reduceMotion
                        )
                        .frame(width: 220, height: 220)

                        VStack(spacing: QueueSpacing.xs) {
                            Text(timeLabel(remaining))
                                .font(QueueTypography.monoTimer(56))
                                .foregroundStyle(QueueColors.textPrimary)
                                .contentTransition(.numericText())
                                .accessibilityLabel("Time remaining \(spokenTime(remaining))")

                            statusCaption
                        }
                    }
                }
                .onChange(of: remaining) { _, newValue in
                    if newValue <= 0, session?.state == .running {
                        Task { await evaluateExpiry() }
                    }
                }
            }

            if companionVisible {
                CompanionAnimationView(state: companionState, reduceMotion: reduceMotion)
                    .frame(width: 240, height: 240)
                    .frame(maxWidth: .infinity)
                    .accessibilityHidden(false)
            }

            Spacer(minLength: QueueSpacing.sm)

            if focusAlertsDenied {
                Text("Focus alerts are off. You can turn them on in iOS Settings.")
                    .font(QueueTypography.caption())
                    .foregroundStyle(QueueColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, QueueSpacing.xl)
            }

            controls
                .padding(.horizontal, QueueSpacing.xl)
                .padding(.bottom, QueueSpacing.lg)
        }
    }

    @ViewBuilder
    private var statusCaption: some View {
        if let session, session.state == .expired {
            Text("Time’s up — finish when you’re ready")
                .font(QueueTypography.caption())
                .foregroundStyle(QueueColors.accent)
                .transition(.opacity)
        } else if session?.state == .paused {
            Text("Paused")
                .font(QueueTypography.caption())
                .foregroundStyle(QueueColors.textSecondary)
        } else {
            Text(currentTask.difficulty.displayName + " · " + durationLabel(currentTask.estimatedDuration))
                .font(QueueTypography.caption())
                .foregroundStyle(QueueColors.textSecondary)
        }
    }

    private var controls: some View {
        VStack(spacing: QueueSpacing.sm) {
            Button("Complete") {
                Task { await complete() }
            }
            .buttonStyle(QueuePrimaryButtonStyle())
            .accessibilityHint("Marks the task done and awards XP")

            HStack(spacing: QueueSpacing.sm) {
                if session?.state == .paused {
                    Button("Resume") {
                        Task { await resume() }
                    }
                    .buttonStyle(QueueSecondaryButtonStyle())
                } else if session?.state == .running {
                    Button("Pause") {
                        Task { await pause() }
                    }
                    .buttonStyle(QueueSecondaryButtonStyle())
                }

                if session?.state == .running || session?.state == .paused || session?.state == .expired {
                    Button("+5 min") {
                        Task { await extend() }
                    }
                    .buttonStyle(QueueSecondaryButtonStyle())
                    .accessibilityLabel("Extend five minutes")
                }
            }
        }
    }

    // MARK: - Actions

    private func bootstrapFocus() async {
        guard !didBootstrap else { return }
        didBootstrap = true
        companionState = .preparing
        withAnimation(QueueMotion.prefer(QueueMotion.standard, reduceMotion: reduceMotion)) {
            contentAppeared = true
        }
        do {
            let started = try await services.taskRepository?.beginFocus(
                taskID: currentTask.id,
                plannedDuration: currentTask.estimatedDuration
            )
            session = started
            await refreshAlertPermission()
            await services.refreshFocusSnapshot()
            // Brief preparing beat, then settle into working.
            try? await Task.sleep(nanoseconds: reduceMotion ? 0 : 280_000_000)
            withAnimation(QueueMotion.prefer(QueueMotion.standard, reduceMotion: reduceMotion)) {
                companionState = visualState(for: started?.state)
            }
            if started?.state == .running {
                QueueHaptics.softTap(reduceMotion: reduceMotion)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func finishAfterCelebration(outcome: FocusCompletionOutcome) {
        services.offerUndo(forTaskTitle: outcome.task.title)
        completionOutcome = nil
        nextOffer = nil
        autoStartStartedAt = nil
        breakStartedAt = nil
        dismiss()
    }

    private func takeBreak() {
        guard nextOffer != nil else { return }
        autoStartCancelled = true
        autoStartStartedAt = nil
        breakStartedAt = Date()
    }

    private func cancelAutoStart() {
        autoStartCancelled = true
        autoStartStartedAt = nil
    }

    private func autoStartElapsed() {
        guard let offer = nextOffer, let started = autoStartStartedAt, let duration = offer.autoStartCountdown else {
            return
        }
        let decision = NextBlockHandoffResolver.autoStart(
            cancelled: autoStartCancelled,
            startedAt: started,
            duration: duration,
            now: Date()
        )
        guard decision == .startNext else { return }
        Task { await startNext(offer.task) }
    }

    private func skipBreak() {
        guard let next = nextOffer?.task else { return }
        guard NextBlockHandoffResolver.resolveBreak(.skip) == .startNext else { return }
        Task { await startNext(next) }
    }

    private func breakElapsed() {
        guard let offer = nextOffer, let started = breakStartedAt else { return }
        let decision = NextBlockHandoffResolver.afterBreak(
            skipped: false,
            startedAt: started,
            duration: offer.breakDuration,
            now: Date()
        )
        guard decision == .startNext else { return }
        Task { await startNext(offer.task) }
    }

    private func leaveBreak() {
        guard NextBlockHandoffResolver.resolveBreak(.leave) == .stay,
              let outcome = completionOutcome
        else { return }
        finishAfterCelebration(outcome: outcome)
    }

    /// Starts focus on the following block. `beginFocus` schedules that block's end alert
    /// and the widget snapshot is rebuilt from the new session, so both drop the finished task.
    private func startNext(_ next: QueueTask) async {
        guard !handoffLocked else { return }
        handoffLocked = true
        do {
            let started = try await services.taskRepository?.beginFocus(
                taskID: next.id,
                plannedDuration: next.estimatedDuration
            )
            guard let started else {
                handoffLocked = false
                return
            }
            currentTask = next
            session = started
            await refreshAlertPermission()
            await services.refreshFocusSnapshot()
            withAnimation(QueueMotion.prefer(QueueMotion.standard, reduceMotion: reduceMotion)) {
                completionOutcome = nil
                nextOffer = nil
                autoStartStartedAt = nil
                autoStartCancelled = false
                breakStartedAt = nil
                contentAppeared = true
                companionState = .preparing
            }
            handoffLocked = false
            try? await Task.sleep(nanoseconds: reduceMotion ? 0 : 280_000_000)
            guard completionOutcome == nil, breakStartedAt == nil, session?.id == started.id else { return }
            withAnimation(QueueMotion.prefer(QueueMotion.standard, reduceMotion: reduceMotion)) {
                companionState = visualState(for: started.state)
            }
            if started.state == .running {
                QueueHaptics.softTap(reduceMotion: reduceMotion)
            }
        } catch {
            handoffLocked = false
            autoStartStartedAt = nil
            autoStartCancelled = true
            errorMessage = error.localizedDescription
        }
    }

    private func pause() async {
        do {
            session = try await services.taskRepository?.pauseFocus(taskID: currentTask.id)
            await services.refreshFocusSnapshot()
            withAnimation(QueueMotion.prefer(QueueMotion.quick, reduceMotion: reduceMotion)) {
                companionState = .paused
            }
            QueueHaptics.softTap(reduceMotion: reduceMotion)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func resume() async {
        do {
            session = try await services.taskRepository?.resumeFocus(taskID: currentTask.id)
            await refreshAlertPermission()
            await services.refreshFocusSnapshot()
            withAnimation(QueueMotion.prefer(QueueMotion.standard, reduceMotion: reduceMotion)) {
                companionState = .working
            }
            QueueHaptics.softTap(reduceMotion: reduceMotion)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func extend() async {
        do {
            session = try await services.taskRepository?.extendFocus(by: 5 * 60)
            await refreshAlertPermission()
            await services.refreshFocusSnapshot()
            withAnimation(QueueMotion.prefer(QueueMotion.quick, reduceMotion: reduceMotion)) {
                if session?.state == .running {
                    companionState = .working
                }
            }
            QueueHaptics.softTap(reduceMotion: reduceMotion)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func evaluateExpiry() async {
        do {
            let snapped = try await services.taskRepository?.evaluateFocusExpiry()
            session = snapped
            await services.refreshFocusSnapshot()
            if snapped?.state == .expired {
                withAnimation(QueueMotion.prefer(QueueMotion.standard, reduceMotion: reduceMotion)) {
                    companionState = .timerExpired
                }
            }
        } catch {
            // Soft-fail; TimelineView will keep showing clamped remaining time.
        }
    }

    private func refreshAlertPermission() async {
        focusAlertsDenied = await services.focusAlertCenter.authorizationStatus() == .denied
    }

    private func visualState(for timerState: FocusTimerState?) -> CompanionVisualState {
        switch timerState {
        case .running: return .working
        case .paused: return .paused
        case .expired: return .timerExpired
        case .completed: return .celebrating
        case .idle, .none: return .preparing
        }
    }

    private func complete() async {
        do {
            guard let outcome = try await services.taskRepository?.completeFocus(taskID: currentTask.id) else {
                return
            }
            let tasks = await services.taskRepository?.tasks() ?? []
            let autoStart = UserPreferencesStore.entity(in: modelContext).autoStartNextTask
            let offer = NextBlockPlanner.offer(
                after: outcome.task.id,
                in: tasks,
                autoStartNextTask: autoStart
            )
            await services.refreshXP()
            await services.refreshFocusSnapshot()
            withAnimation(QueueMotion.prefer(QueueMotion.celebration, reduceMotion: reduceMotion)) {
                companionState = outcome.award.levelsCrossed.isEmpty ? .celebrating : .levelUp
                nextOffer = offer
                autoStartCancelled = false
                breakStartedAt = nil
                autoStartStartedAt = offer?.willAutoStart == true ? Date() : nil
                completionOutcome = outcome
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Formatting

    private func displayedRemaining(at now: Date) -> TimeInterval {
        guard let session else { return currentTask.estimatedDuration }
        return session.remaining(at: now)
    }

    private func ringProgress(at now: Date) -> Double {
        guard let session else { return 1 }
        let total = max(1, session.totalPlanned)
        let remaining = session.remaining(at: now)
        return remaining / total
    }

    private func timeLabel(_ interval: TimeInterval) -> String {
        FocusTimerFormatting.clock(interval)
    }

    private func spokenTime(_ interval: TimeInterval) -> String {
        FocusTimerFormatting.spoken(interval)
    }

    private func durationLabel(_ interval: TimeInterval) -> String {
        "\(max(1, Int(interval / 60))) min estimate"
    }
}

/// A five-minute pause before the next block. The countdown is derived from `startedAt`.
private struct FocusBreakView: View {
    let nextTask: QueueTask
    let startedAt: Date
    let duration: TimeInterval
    var onSkip: () -> Void
    var onElapsed: () -> Void
    var onLeave: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.queueCompanionVisible) private var companionVisible
    @Environment(\.scenePhase) private var scenePhase
    @State private var didNotifyElapsed = false

    var body: some View {
        VStack(spacing: QueueSpacing.lg) {
            Spacer(minLength: QueueSpacing.sm)

            if companionVisible {
                CompanionAnimationView(state: .idle, reduceMotion: reduceMotion)
                    .frame(height: 120)
            }

            Text(NextBlockCopy.breakHeading)
                .font(QueueTypography.title(30))
                .foregroundStyle(QueueColors.textPrimary)
                .accessibilityAddTraits(.isHeader)

            TimelineView(.periodic(from: startedAt, by: reduceMotion ? 1 : 0.25)) { context in
                let remaining = CountdownClock.remaining(
                    startedAt: startedAt,
                    duration: duration,
                    now: context.date
                )
                let progress = duration > 0 ? remaining / duration : 0
                ZStack {
                    FocusCountdownRing(
                        progress: progress,
                        isExpired: false,
                        isPaused: false,
                        reduceMotion: reduceMotion
                    )
                    .frame(width: 220, height: 220)

                    Text(FocusTimerFormatting.clock(remaining))
                        .font(QueueTypography.monoTimer(56))
                        .foregroundStyle(QueueColors.textPrimary)
                        .accessibilityLabel("Break time remaining \(FocusTimerFormatting.spoken(remaining))")
                }
            }

            Text(NextBlockCopy.breakNextLine(taskTitle: nextTask.title))
                .font(QueueTypography.body())
                .foregroundStyle(QueueColors.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, QueueSpacing.xl)

            Spacer(minLength: QueueSpacing.sm)

            VStack(spacing: QueueSpacing.sm) {
                Button(NextBlockCopy.skipBreakTitle, action: onSkip)
                    .buttonStyle(QueueSecondaryButtonStyle())
                    .accessibilityHint("Starts the next task now")
                Button(NextBlockCopy.leaveBreakTitle, action: onLeave)
                    .font(QueueTypography.caption())
                    .foregroundStyle(QueueColors.textSecondary)
                    .frame(minHeight: QueueSpacing.minTouch)
                    .accessibilityHint("Leaves the break. The next task stays in the queue.")
            }
            .padding(.horizontal, QueueSpacing.xl)
            .padding(.bottom, QueueSpacing.lg)
        }
        .task(id: startedAt) {
            let finished = await CountdownClock.waitUntilComplete(startedAt: startedAt, duration: duration)
            guard finished, !Task.isCancelled else { return }
            notifyElapsed()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            if CountdownClock.isComplete(startedAt: startedAt, duration: duration, now: Date()) {
                notifyElapsed()
            }
        }
    }

    private func notifyElapsed() {
        guard !didNotifyElapsed else { return }
        guard CountdownClock.isComplete(startedAt: startedAt, duration: duration, now: Date()) else { return }
        didNotifyElapsed = true
        onElapsed()
    }
}
