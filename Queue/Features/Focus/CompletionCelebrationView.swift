import SwiftUI
import QueueCore

/// Skippable completion celebration — XP count-up, companion reaction, level fill.
struct CompletionCelebrationView: View {
    @Environment(\.queueTheme) private var queueTheme
    let outcome: FocusCompletionOutcome
    var offer: NextBlockOffer?
    var autoStartStartedAt: Date?
    var onContinue: () -> Void
    var onSkip: () -> Void
    var onStartNext: () -> Void
    var onTakeBreak: () -> Void
    var onCancelAutoStart: () -> Void
    var onAutoStartElapsed: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.queueCompanionVisible) private var companionVisible
    @State private var displayedXP: Int = 0
    @State private var showBreakdown = false
    @State private var appeared = false
    @State private var levelFill: Double
    @State private var currentLevelName: String
    @State private var nextLevelName: String?
    @State private var showLevelUpBadge = false
    @State private var levelFillTask: Task<Void, Never>?

    /// Same-level fill, matching the pre-level-up celebration.
    private static let sameLevelFillDuration: TimeInterval = 0.9
    /// Lets a snap commit before the next forward fill, so SwiftUI does not
    /// interpolate across the reset.
    private static let segmentCommitDelay: TimeInterval = 0.032
    /// Holds a completed level at full before the bar snaps empty.
    private static let levelResetHold: TimeInterval = 0.12

    private var levelUp: Bool { !outcome.award.levelsCrossed.isEmpty }

    init(
        outcome: FocusCompletionOutcome,
        offer: NextBlockOffer? = nil,
        autoStartStartedAt: Date? = nil,
        onContinue: @escaping () -> Void,
        onSkip: @escaping () -> Void,
        onStartNext: @escaping () -> Void = {},
        onTakeBreak: @escaping () -> Void = {},
        onCancelAutoStart: @escaping () -> Void = {},
        onAutoStartElapsed: @escaping () -> Void = {}
    ) {
        self.outcome = outcome
        self.offer = offer
        self.autoStartStartedAt = autoStartStartedAt
        self.onContinue = onContinue
        self.onSkip = onSkip
        self.onStartNext = onStartNext
        self.onTakeBreak = onTakeBreak
        self.onCancelAutoStart = onCancelAutoStart
        self.onAutoStartElapsed = onAutoStartElapsed
        let opening = LevelBarSequence.segments(
            from: outcome.award.previousXP,
            to: outcome.award.totalXP
        ).first
        _levelFill = State(initialValue: opening?.startFraction ?? 0)
        _currentLevelName = State(initialValue: opening?.currentLevel.name ?? "")
        _nextLevelName = State(initialValue: opening?.nextLevel?.name)
    }

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: QueueSpacing.lg) {
                        Spacer(minLength: 0)

                        if companionVisible {
                            CompanionAnimationView(
                                state: levelUp ? .levelUp : .celebrating,
                                reduceMotion: reduceMotion
                            )
                            .frame(height: offer == nil ? 150 : 110)
                            .scaleEffect(appeared ? 1 : 0.92)
                            .opacity(appeared ? 1 : 0)
                        }

                        Text("Nice work")
                            .font(QueueTypography.title(30))
                            .foregroundStyle(QueueColors.textPrimary)
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 8)

                        Text(outcome.task.title)
                            .font(QueueTypography.body())
                            .foregroundStyle(QueueColors.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, QueueSpacing.xl)
                            .opacity(appeared ? 1 : 0)

                        VStack(spacing: QueueSpacing.sm) {
                            Text("+\(displayedXP) XP")
                                .font(QueueTypography.display(44))
                                .foregroundStyle(QueueColors.rewardMark)
                                .contentTransition(.numericText())
                                .accessibilityLabel("\(outcome.award.awardedXP) experience points earned")
                                .accessibilityIdentifier(QueueAccessibilityID.celebrationXP)

                            if showBreakdown {
                                Text(breakdownCaption)
                                    .font(QueueTypography.caption())
                                    .foregroundStyle(QueueColors.textSecondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, QueueSpacing.xl)
                                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                            }

                            levelBar
                                .padding(.horizontal, QueueSpacing.xl)
                                .padding(.top, QueueSpacing.xs)

                            if showLevelUpBadge, let crossed = outcome.award.levelsCrossed.last {
                                Text("Level up — \(crossed.name)")
                                    .font(QueueTypography.headline(17))
                                    .foregroundStyle(QueueColors.onAccent)
                                    .padding(.horizontal, QueueSpacing.md)
                                    .padding(.vertical, QueueSpacing.xs)
                                    .background(
                                        Capsule(style: .continuous)
                                            .fill(QueueColors.accent)
                                    )
                                    .transition(.scale.combined(with: .opacity))
                            }
                        }

                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height)
                }
                .scrollBounceBehavior(.basedOnSize)
            }

            actions
                .padding(.horizontal, QueueSpacing.xl)
                .padding(.top, QueueSpacing.sm)
                .padding(.bottom, QueueSpacing.lg)
                .opacity(appeared ? 1 : 0)
        }
        .onAppear { runEntrance() }
        .onDisappear { levelFillTask?.cancel() }
        .environment(\.queueTheme, queueTheme)
        .task(id: autoStartStartedAt) {
            await runAutoStartCountdown()
        }
    }

    @ViewBuilder
    private var actions: some View {
        VStack(spacing: QueueSpacing.sm) {
            if let offer {
                if let autoStartStartedAt, let duration = offer.autoStartCountdown {
                    autoStartCountdown(taskTitle: offer.task.title, startedAt: autoStartStartedAt, duration: duration)
                }
                Button {
                    onStartNext()
                } label: {
                    Text(NextBlockCopy.startButtonTitle(taskTitle: offer.task.title))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                }
                .buttonStyle(QueuePrimaryButtonStyle())
                .accessibilityHint("Starts a focus block for the next task")

                Button(NextBlockCopy.breakButtonTitle, action: onTakeBreak)
                    .buttonStyle(QueueSecondaryButtonStyle())
                    .accessibilityHint("Waits five minutes, then starts the next task. You can skip the break.")

                textAction("Continue", action: onContinue)
            } else {
                Button("Continue", action: onContinue)
                    .buttonStyle(QueuePrimaryButtonStyle())
            }
            textAction("Skip celebration", action: onSkip)
        }
    }

    private func textAction(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(QueueTypography.caption())
            .foregroundStyle(QueueColors.textSecondary)
            .frame(minHeight: QueueSpacing.minTouch)
    }

    private func autoStartCountdown(taskTitle: String, startedAt: Date, duration: TimeInterval) -> some View {
        TimelineView(.periodic(from: startedAt, by: reduceMotion ? 1 : 0.25)) { context in
            let remaining = CountdownClock.remaining(startedAt: startedAt, duration: duration, now: context.date)
            let seconds = NextBlockCopy.displayedSeconds(remaining: remaining)
            let status = NextBlockCopy.autoStartStatus(taskTitle: taskTitle, secondsRemaining: seconds)
            VStack(spacing: QueueSpacing.xxs) {
                Text(status)
                    .font(QueueTypography.caption())
                    .foregroundStyle(QueueColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .accessibilityLabel(status)
                Button(NextBlockCopy.cancelAutoStartTitle, action: onCancelAutoStart)
                    .font(QueueTypography.headline(17))
                    .foregroundStyle(QueueColors.rewardMark)
                    .frame(minHeight: QueueSpacing.minTouch)
                    .accessibilityHint("Stays on this celebration")
            }
        }
    }

    private func runAutoStartCountdown() async {
        guard let started = autoStartStartedAt, let duration = offer?.autoStartCountdown else { return }
        let finished = await CountdownClock.waitUntilComplete(startedAt: started, duration: duration)
        guard finished, !Task.isCancelled, autoStartStartedAt != nil else { return }
        onAutoStartElapsed()
    }

    private var levelBar: some View {
        VStack(alignment: .leading, spacing: QueueSpacing.xs) {
            HStack {
                Text(currentLevelName)
                    .font(QueueTypography.caption())
                    .foregroundStyle(QueueColors.textSecondary)
                Spacer()
                if let nextLevelName {
                    Text(nextLevelName)
                        .font(QueueTypography.caption())
                        .foregroundStyle(QueueColors.textSecondary)
                }
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(QueueColors.surface)
                    Capsule()
                        .fill(QueueColors.rewardMark)
                        .frame(width: proxy.size.width * levelFill)
                }
            }
            .frame(height: 8)
            .accessibilityLabel("Level progress")
            .accessibilityValue("\(Int(levelFill * 100)) percent")
        }
    }

    private var breakdownCaption: String {
        let b = outcome.award.breakdown
        var parts = ["\(b.difficulty.displayName) · \(b.estimatedMinutes) min"]
        if b.punctualityBonus > 0 {
            if b.finishedWithinBudget {
                parts.append("on-time +\(b.punctualityBonus)")
            } else if b.usedSoftGrace {
                parts.append("near budget +\(b.punctualityBonus)")
            }
        } else if b.budgetRatio > 1 {
            parts.append("finished over budget — still rewarded")
        }
        return parts.joined(separator: " · ")
    }

    private func runEntrance() {
        QueueHaptics.success(reduceMotion: reduceMotion)

        withAnimation(QueueMotion.prefer(QueueMotion.celebration, reduceMotion: reduceMotion)) {
            appeared = true
        }

        animateXP()
        animateLevelFill()
    }

    private func animateXP() {
        let target = outcome.award.awardedXP
        guard !reduceMotion, target > 0 else {
            displayedXP = target
            showBreakdown = true
            revealLevelUpIfNeeded()
            return
        }

        let duration = QueueMotion.xpCountDuration
        let steps = 28
        let stepValue = max(1, Int(ceil(Double(target) / Double(steps))))
        var current = 0
        let interval = duration / Double(steps)

        Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { timer in
            current = min(target, current + stepValue)
            withAnimation(.easeOut(duration: 0.05)) {
                displayedXP = current
            }
            if current >= target {
                timer.invalidate()
                withAnimation(QueueMotion.standard) {
                    showBreakdown = true
                }
                revealLevelUpIfNeeded()
            }
        }
    }

    private func animateLevelFill() {
        let segments = LevelBarSequence.segments(
            from: outcome.award.previousXP,
            to: outcome.award.totalXP
        )
        guard let final = segments.last else { return }

        // Reduce Motion snaps to the final level. Interpolating would shrink
        // the bar when the new level's fraction is smaller than the old one.
        if reduceMotion {
            showLevel(final, fraction: final.endFraction)
            return
        }

        let duration = fillDuration(for: segments)
        levelFillTask?.cancel()
        levelFillTask = Task { @MainActor in
            for segment in segments {
                guard !Task.isCancelled else { return }
                showLevel(segment, fraction: segment.startFraction)
                guard await pause(Self.segmentCommitDelay) else { return }
                if segment.endFraction > segment.startFraction {
                    guard await animateFill(to: segment.endFraction, duration: duration) else { return }
                }
                if segment.resetAfter {
                    guard await pause(Self.levelResetHold) else { return }
                }
            }
        }
    }

    private func fillDuration(for segments: [LevelBarSegment]) -> TimeInterval {
        guard segments.contains(where: \.resetAfter) else {
            return Self.sameLevelFillDuration
        }
        let moving = segments.filter { $0.endFraction > $0.startFraction }.count
        return QueueMotion.levelUpDuration / Double(max(moving, 1))
    }

    private func showLevel(_ segment: LevelBarSegment, fraction: Double) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        transaction.animation = nil
        withTransaction(transaction) {
            currentLevelName = segment.currentLevel.name
            nextLevelName = segment.nextLevel?.name
            levelFill = fraction
        }
    }

    /// Animates the fill forward. Returns false when the celebration was skipped.
    private func animateFill(to fraction: Double, duration: TimeInterval) async -> Bool {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            withAnimation(.easeInOut(duration: duration), completionCriteria: .logicallyComplete) {
                levelFill = fraction
            } completion: {
                // Resume on a later turn so a synchronous completion cannot
                // resume the continuation before it starts waiting.
                DispatchQueue.main.async {
                    continuation.resume()
                }
            }
        }
        return !Task.isCancelled
    }

    private func pause(_ seconds: TimeInterval) async -> Bool {
        do {
            try await Task.sleep(nanoseconds: UInt64((seconds * 1_000_000_000).rounded()))
            return !Task.isCancelled
        } catch {
            return false
        }
    }

    private func revealLevelUpIfNeeded() {
        guard levelUp else { return }
        if !reduceMotion {
            QueueHaptics.levelUp()
        }
        withAnimation(QueueMotion.prefer(QueueMotion.celebration, reduceMotion: reduceMotion)) {
            showLevelUpBadge = true
        }
    }
}
