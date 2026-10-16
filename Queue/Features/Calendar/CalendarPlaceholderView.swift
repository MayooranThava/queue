import SwiftUI

struct CalendarPlaceholderView: View {
    var body: some View {
        ZStack {
            QueueColors.background.ignoresSafeArea()
            VStack(spacing: QueueSpacing.md) {
                Image(systemName: "calendar")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(QueueColors.sageDeep)
                Text("Calendar")
                    .font(QueueTypography.title(28))
                    .foregroundStyle(QueueColors.primaryText)
                Text("Apple Calendar and Smart Gaps arrive in a later phase. Your queue works without them.")
                    .font(QueueTypography.body())
                    .foregroundStyle(QueueColors.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, QueueSpacing.xl)
            }
        }
        .navigationTitle("Calendar")
    }
}
