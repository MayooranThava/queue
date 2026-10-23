import SwiftUI
import QueueCore

struct QueuePrimaryButtonStyle: ButtonStyle {
    var isDestructive: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        ThemedPrimaryButton(isDestructive: isDestructive, isPressed: configuration.isPressed) {
            configuration.label
        }
    }
}

struct QueueSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        ThemedSecondaryButton(isPressed: configuration.isPressed) {
            configuration.label
        }
    }
}

struct QueueTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        ThemedTextFieldChrome {
            configuration
        }
    }
}

private struct ThemedPrimaryButton<Label: View>: View {
    var isDestructive: Bool
    var isPressed: Bool
    @ViewBuilder var label: () -> Label
    @Environment(\.queueTheme) private var queueTheme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        label()
            .font(QueueTypography.headline(17))
            .foregroundStyle(color(.onPrimary))
            .frame(maxWidth: .infinity, minHeight: QueueSpacing.minTouch)
            .background(
                RoundedRectangle(cornerRadius: QueueSpacing.cornerMinimal, style: .continuous)
                    .fill(color(isDestructive ? .danger : .primary))
            )
            .opacity(isPressed ? 0.88 : 1)
            .animation(.easeOut(duration: 0.15), value: isPressed)
    }

    private func color(_ role: QueueColorRole) -> Color {
        QueueColors.concrete(
            role,
            theme: queueTheme,
            scheme: colorScheme,
            increasedContrast: contrast == .increased
        )
    }
}

private struct ThemedSecondaryButton<Label: View>: View {
    var isPressed: Bool
    @ViewBuilder var label: () -> Label
    @Environment(\.queueTheme) private var queueTheme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        label()
            .font(QueueTypography.headline(17))
            .foregroundStyle(color(.textPrimary))
            .frame(maxWidth: .infinity, minHeight: QueueSpacing.minTouch)
            .background(
                RoundedRectangle(cornerRadius: QueueSpacing.cornerMinimal, style: .continuous)
                    .fill(color(.surface))
            )
            .opacity(isPressed ? 0.88 : 1)
    }

    private func color(_ role: QueueColorRole) -> Color {
        QueueColors.concrete(
            role,
            theme: queueTheme,
            scheme: colorScheme,
            increasedContrast: contrast == .increased
        )
    }
}

private struct ThemedTextFieldChrome<Content: View>: View {
    @ViewBuilder var content: () -> Content
    @Environment(\.queueTheme) private var queueTheme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        content()
            .padding(QueueSpacing.md)
            .background(
                RoundedRectangle(cornerRadius: QueueSpacing.cornerMinimal, style: .continuous)
                    .fill(
                        QueueColors.concrete(
                            .surface,
                            theme: queueTheme,
                            scheme: colorScheme,
                            increasedContrast: contrast == .increased
                        )
                        .opacity(0.55)
                    )
            )
    }
}
