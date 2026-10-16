import SwiftUI
import QueueCore

/// Immersive Focus arrives in Phase 2. This shell establishes navigation & styling.
struct FocusPlaceholderView: View {
    let task: QueueTask
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            QueueColors.charcoal.ignoresSafeArea()
            VStack(spacing: QueueSpacing.lg) {
                Text(task.title)
                    .font(QueueTypography.title(28))
                    .foregroundStyle(QueueColors.ivory)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, QueueSpacing.xl)

                Text(timeLabel(task.estimatedDuration))
                    .font(QueueTypography.monoTimer(56))
                    .foregroundStyle(QueueColors.ivory)

                CompanionAnimationView(state: .preparing, reduceMotion: false)
                    .frame(height: 160)

                Text("Focus engine lands in Phase 2 — reliable timestamps, pause, extend, and expiry.")
                    .font(QueueTypography.body(15))
                    .foregroundStyle(QueueColors.ivory.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, QueueSpacing.xl)

                Button("Close") { dismiss() }
                    .buttonStyle(QueueSecondaryButtonStyle())
                    .padding(.horizontal, QueueSpacing.xl)
            }
        }
        .preferredColorScheme(.dark)
    }

    private func timeLabel(_ interval: TimeInterval) -> String {
        let total = Int(interval)
        let m = total / 60
        let s = total % 60
        return String(format: "%02d:%02d", m, s)
    }
}
