import SwiftUI

/// Shown when the on-disk store cannot be opened. Offers a retry and does not
/// offer a way to erase or replace the store.
struct PersistenceFailureView: View {
    let error: Error
    var retry: () -> Void
    @Environment(\.queueTheme) private var queueTheme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: QueueSpacing.md) {
                Text("Couldn't open your tasks")
                    .font(QueueTypography.title())
                    .foregroundStyle(QueueColors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Your saved tasks are still on this device. Try opening them again.")
                    .font(QueueTypography.body())
                    .foregroundStyle(QueueColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .font(QueueTypography.caption())
                    .foregroundStyle(QueueColors.textSecondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Try Again", action: retry)
                    .buttonStyle(QueuePrimaryButtonStyle())
                    .padding(.top, QueueSpacing.sm)
            }
            .padding(QueueSpacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(QueueColors.background)
        .environment(\.queueTheme, queueTheme)
    }

    private var detail: String {
        let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if message.isEmpty {
            return String(describing: error)
        }
        return message
    }
}
