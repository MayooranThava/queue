import SwiftUI
import QueueCore

struct ProgressPlaceholderView: View {
    @EnvironmentObject private var services: AppServices

    var body: some View {
        let progress = LevelTable.progress(towardNext: services.totalXP)

        ZStack {
            QueueColors.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: QueueSpacing.lg) {
                    VStack(alignment: .leading, spacing: QueueSpacing.xs) {
                        Text(progress.current.name)
                            .font(QueueTypography.title(32))
                            .foregroundStyle(QueueColors.primaryText)
                        Text("\(services.totalXP) XP")
                            .font(QueueTypography.display(40))
                            .foregroundStyle(QueueColors.rewardDeep)
                    }

                    VStack(alignment: .leading, spacing: QueueSpacing.sm) {
                        if let next = progress.next {
                            Text("Next: \(next.name)")
                                .font(QueueTypography.caption())
                                .foregroundStyle(QueueColors.secondaryText)
                        } else {
                            Text("Top level — keep the streak going")
                                .font(QueueTypography.caption())
                                .foregroundStyle(QueueColors.secondaryText)
                        }

                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(QueueColors.secondarySurface)
                                Capsule()
                                    .fill(QueueColors.reward)
                                    .frame(width: proxy.size.width * progress.fraction)
                            }
                        }
                        .frame(height: 10)
                        .accessibilityLabel("Level progress")
                        .accessibilityValue("\(Int(progress.fraction * 100)) percent")
                    }
                    .padding(QueueSpacing.lg)
                    .background(
                        RoundedRectangle(cornerRadius: QueueSpacing.cornerSoft, style: .continuous)
                            .fill(QueueColors.secondarySurface.opacity(0.55))
                    )

                    VStack(alignment: .leading, spacing: QueueSpacing.sm) {
                        Text("How XP works")
                            .font(QueueTypography.headline(17))
                            .foregroundStyle(QueueColors.primaryText)
                        Text(
                            "Base XP scales with difficulty and estimate length. Finish within budget for a punctuality bonus. Going over never subtracts XP — you still get rewarded for finishing."
                        )
                        .font(QueueTypography.body(15))
                        .foregroundStyle(QueueColors.secondaryText)
                    }

                    Spacer(minLength: QueueSpacing.xxl)
                }
                .padding(QueueSpacing.lg)
            }
        }
        .navigationTitle("Progress")
        .task {
            await services.refreshXP()
        }
    }
}
