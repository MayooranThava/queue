import SwiftUI

struct ProgressPlaceholderView: View {
    var body: some View {
        ZStack {
            QueueColors.background.ignoresSafeArea()
            VStack(spacing: QueueSpacing.md) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(QueueColors.sageDeep)
                Text("Progress")
                    .font(QueueTypography.title(28))
                    .foregroundStyle(QueueColors.primaryText)
                Text("XP, levels, and streaks will appear here once the reward engine is wired to completion.")
                    .font(QueueTypography.body())
                    .foregroundStyle(QueueColors.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, QueueSpacing.xl)
            }
        }
        .navigationTitle("Progress")
    }
}
