import SwiftUI
import QueueCore

/// Skippable completion celebration — XP count-up, companion reaction, next cue.
struct CompletionCelebrationView: View {
    let outcome: FocusCompletionOutcome
    var onContinue: () -> Void
    var onSkip: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var displayedXP: Int = 0
    @State private var showBreakdown = false

    private var levelUp: Bool { !outcome.award.levelsCrossed.isEmpty }

    var body: some View {
        VStack(spacing: QueueSpacing.lg) {
            Spacer()

            CompanionAnimationView(
                state: levelUp ? .levelUp : .celebrating,
                reduceMotion: reduceMotion
            )
            .frame(height: 150)

            Text("Nice work")
                .font(QueueTypography.title(30))
                .foregroundStyle(QueueColors.ivory)

            Text(outcome.task.title)
                .font(QueueTypography.body())
                .foregroundStyle(QueueColors.ivory.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, QueueSpacing.xl)

            VStack(spacing: QueueSpacing.xs) {
                Text("+\(displayedXP) XP")
                    .font(QueueTypography.display(44))
                    .foregroundStyle(QueueColors.reward)
                    .contentTransition(.numericText())
                    .accessibilityLabel("\(outcome.award.awardedXP) experience points earned")

                if showBreakdown {
                    Text(breakdownCaption)
                        .font(QueueTypography.caption())
                        .foregroundStyle(QueueColors.ivory.opacity(0.65))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, QueueSpacing.xl)
                        .transition(.opacity)
                }

                if levelUp, let crossed = outcome.award.levelsCrossed.last {
                    Text("Level up — \(crossed.name)")
                        .font(QueueTypography.headline(17))
                        .foregroundStyle(QueueColors.sage)
                        .padding(.top, QueueSpacing.xs)
                }
            }

            Spacer()

            VStack(spacing: QueueSpacing.sm) {
                Button("Continue", action: onContinue)
                    .buttonStyle(QueuePrimaryButtonStyle(onDarkSurface: true))
                Button("Skip celebration", action: onSkip)
                    .font(QueueTypography.caption())
                    .foregroundStyle(QueueColors.ivory.opacity(0.55))
                    .frame(minHeight: QueueSpacing.minTouch)
            }
            .padding(.horizontal, QueueSpacing.xl)
            .padding(.bottom, QueueSpacing.lg)
        }
        .onAppear { animateXP() }
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

    private func animateXP() {
        let target = outcome.award.awardedXP
        guard !reduceMotion, target > 0 else {
            displayedXP = target
            showBreakdown = true
            return
        }
        let steps = min(target, 24)
        let stepValue = max(1, target / steps)
        var current = 0
        Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { timer in
            current = min(target, current + stepValue)
            displayedXP = current
            if current >= target {
                timer.invalidate()
                withAnimation(.easeOut(duration: 0.25)) {
                    showBreakdown = true
                }
            }
        }
    }
}
