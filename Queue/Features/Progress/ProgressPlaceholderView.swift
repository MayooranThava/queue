import SwiftUI
import QueueCore

struct ProgressPlaceholderView: View {
    @EnvironmentObject private var services: AppServices
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.queueTheme) private var queueTheme
    @State private var animatedFraction: Double = 0

    var body: some View {
        let progress = LevelTable.progress(towardNext: services.totalXP)

        ZStack {
            QueueThemeBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: QueueSpacing.lg) {
                    VStack(alignment: .leading, spacing: QueueSpacing.xs) {
                        Text(progress.current.name)
                            .font(QueueTypography.title(32))
                            .foregroundStyle(QueueColors.textPrimary)
                        Text("\(services.totalXP) XP")
                            .font(QueueTypography.display(40))
                            .foregroundStyle(QueueColors.onAccent)
                            .padding(.horizontal, QueueSpacing.md)
                            .padding(.vertical, QueueSpacing.xs)
                            .background(QueueColors.accent, in: Capsule())
                            .contentTransition(.numericText())
                            .animation(QueueMotion.prefer(QueueMotion.standard, reduceMotion: reduceMotion), value: services.totalXP)
                    }

                    VStack(alignment: .leading, spacing: QueueSpacing.sm) {
                        if let next = progress.next {
                            Text("Next: \(next.name)")
                                .font(QueueTypography.caption())
                                .foregroundStyle(QueueColors.textSecondary)
                        } else {
                            Text("Top level — keep the streak going")
                                .font(QueueTypography.caption())
                                .foregroundStyle(QueueColors.textSecondary)
                        }

                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(QueueColors.surface)
                                Capsule()
                                    .fill(QueueColors.rewardMark)
                                    .frame(width: proxy.size.width * animatedFraction)
                            }
                        }
                        .frame(height: 10)
                        .accessibilityLabel("Level progress")
                        .accessibilityValue("\(Int(progress.fraction * 100)) percent")
                    }
                    .padding(QueueSpacing.lg)
                    .background(
                        RoundedRectangle(cornerRadius: QueueSpacing.cornerSoft, style: .continuous)
                            .fill(QueueColors.surface.opacity(0.55))
                    )

                    VStack(alignment: .leading, spacing: QueueSpacing.sm) {
                        Text("How XP works")
                            .font(QueueTypography.headline(17))
                            .foregroundStyle(QueueColors.textPrimary)
                        Text(
                            "Base XP scales with difficulty and estimate length. Finish within budget for a punctuality bonus. Going over never subtracts XP — you still get rewarded for finishing."
                        )
                        .font(QueueTypography.body(15))
                        .foregroundStyle(QueueColors.textSecondary)
                    }

                    Spacer(minLength: QueueSpacing.xxl)
                }
                .padding(QueueSpacing.lg)
            }
        }
        .navigationTitle("Progress")
        .environment(\.queueTheme, queueTheme)
        .task {
            await services.refreshXP()
            let fraction = LevelTable.progress(towardNext: services.totalXP).fraction
            if reduceMotion {
                animatedFraction = fraction
            } else {
                withAnimation(.easeInOut(duration: 0.8)) {
                    animatedFraction = fraction
                }
            }
        }
        .onChange(of: services.totalXP) { _, newValue in
            let fraction = LevelTable.progress(towardNext: newValue).fraction
            withAnimation(QueueMotion.prefer(.easeInOut(duration: 0.6), reduceMotion: reduceMotion)) {
                animatedFraction = fraction
            }
        }
    }
}
