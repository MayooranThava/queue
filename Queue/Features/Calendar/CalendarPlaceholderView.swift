import SwiftUI

struct CalendarPlaceholderView: View {
    @Environment(\.queueTheme) private var queueTheme

    var body: some View {
        ZStack {
            QueueThemeBackground()
            VStack(spacing: QueueSpacing.md) {
                Image(systemName: "calendar")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(QueueColors.primary)
                Text("Calendar")
                    .font(QueueTypography.title(28))
                    .foregroundStyle(QueueColors.textPrimary)
                Text("Apple Calendar and Smart Gaps arrive in a later phase. Your queue works without them.")
                    .font(QueueTypography.body())
                    .foregroundStyle(QueueColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, QueueSpacing.xl)
            }
        }
        .navigationTitle("Calendar")
        .environment(\.queueTheme, queueTheme)
    }
}
