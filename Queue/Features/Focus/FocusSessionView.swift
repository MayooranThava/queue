import SwiftUI
import QueueCore

/// Immersive Focus: Start immediately begins a timestamp-backed countdown
/// with a working companion. Remaining time is derived, never tick-decremented.
struct FocusSessionView: View {
    let task: QueueTask
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var services: AppServices

    @State private var session: FocusSession?
    @State private var companionState: CompanionVisualState = .preparing
    @State private var errorMessage: String?
    @State private var showExitConfirm = false
    @State private var completionOutcome: FocusCompletionOutcome?
    @State private var didBootstrap = false
    @State private var contentAppeared = false

    var body: some View {
        ZStack {
            QueueColors.charcoal.ignoresSafeArea()

            if let completionOutcome {
                CompletionCelebrationView(
                    outcome: completionOutcome,
                    onContinue: { finishAfterCelebration(outcome: completionOutcome) },
                    onSkip: { finishAfterCelebration(outcome: completionOutcome) }
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
            Button("OK", role: .cancel) { dismiss() }
        } message: {
            Text(errorMessage ?? "")
        }
        .confirmationDialog(
            "Leave focus?",
            isPresented: $showExitConfirm,
            titleVisibility: .visible
        ) {
            Button("Keep focusing", role: .cancel) {}
            Button("Leave anyway") { dismiss() }
        } message: {
            Text("Your timer keeps running from real timestamps — you can return anytime.")
        }
    }

    private var focusContent: some View {
        VStack(spacing: QueueSpacing.lg) {
            HStack {
                Spacer()
                Button {
                    showExitConfirm = true
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(QueueColors.ivory.opacity(0.75))
                        .frame(width: QueueSpacing.minTouch, height: QueueSpacing.minTouch)
                }
                .accessibilityLabel("Close focus")
            }
            .padding(.horizontal, QueueSpacing.md)

            Spacer(minLength: QueueSpacing.sm)

            Text(task.title)
                .font(QueueTypography.title(28))
                .foregroundStyle(QueueColors.ivory)
                .multilineTextAlignment(.center)
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
                                .foregroundStyle(QueueColors.ivory)
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

            CompanionAnimationView(state: companionState, reduceMotion: reduceMotion)
                .frame(height: 150)
                .animation(QueueMotion.prefer(QueueMotion.standard, reduceMotion: reduceMotion), value: companionState)

            Spacer(minLength: QueueSpacing.sm)

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
                .foregroundStyle(QueueColors.reward)
                .transition(.opacity)
        } else if session?.state == .paused {
            Text("Paused")
                .font(QueueTypography.caption())
                .foregroundStyle(QueueColors.ivory.opacity(0.65))
        } else {
            Text(task.difficulty.displayName + " · " + durationLabel(task.estimatedDuration))
                .font(QueueTypography.caption())
                .foregroundStyle(QueueColors.ivory.opacity(0.55))
        }
    }

    private var controls: some View {
        VStack(spacing: QueueSpacing.sm) {
            Button("Complete") {
                Task { await complete() }
            }
            .buttonStyle(QueuePrimaryButtonStyle(onDarkSurface: true))
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
                taskID: task.id,
                plannedDuration: task.estimatedDuration
            )
            session = started
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
        dismiss()
    }

    private func pause() async {
        do {
            session = try await services.taskRepository?.pauseFocus(taskID: task.id)
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
            session = try await services.taskRepository?.resumeFocus(taskID: task.id)
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
            if snapped?.state == .expired {
                withAnimation(QueueMotion.prefer(QueueMotion.standard, reduceMotion: reduceMotion)) {
                    companionState = .timerExpired
                }
            }
        } catch {
            // Soft-fail; TimelineView will keep showing clamped remaining time.
        }
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
            guard let outcome = try await services.taskRepository?.completeFocus(taskID: task.id) else {
                return
            }
            await services.refreshXP()
            withAnimation(QueueMotion.prefer(QueueMotion.celebration, reduceMotion: reduceMotion)) {
                companionState = outcome.award.levelsCrossed.isEmpty ? .celebrating : .levelUp
                completionOutcome = outcome
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Formatting

    private func displayedRemaining(at now: Date) -> TimeInterval {
        guard let session else { return task.estimatedDuration }
        return session.remaining(at: now)
    }

    private func ringProgress(at now: Date) -> Double {
        guard let session else { return 1 }
        let total = max(1, session.totalPlanned)
        let remaining = session.remaining(at: now)
        return remaining / total
    }

    private func timeLabel(_ interval: TimeInterval) -> String {
        let total = Int(interval.rounded(.up))
        let m = total / 60
        let s = total % 60
        return String(format: "%02d:%02d", m, s)
    }

    private func spokenTime(_ interval: TimeInterval) -> String {
        let total = Int(interval.rounded(.up))
        let m = total / 60
        let s = total % 60
        if m == 0 { return "\(s) seconds" }
        if s == 0 { return "\(m) minutes" }
        return "\(m) minutes \(s) seconds"
    }

    private func durationLabel(_ interval: TimeInterval) -> String {
        "\(max(1, Int(interval / 60))) min estimate"
    }
}
