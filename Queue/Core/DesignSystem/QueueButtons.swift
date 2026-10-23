import SwiftUI

struct QueuePrimaryButtonStyle: ButtonStyle {
    var isDestructive: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(QueueTypography.headline(17))
            .foregroundStyle(labelColor)
            .frame(maxWidth: .infinity, minHeight: QueueSpacing.minTouch)
            .background(
                RoundedRectangle(cornerRadius: QueueSpacing.cornerMinimal, style: .continuous)
                    .fill(fillColor)
            )
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }

    private var labelColor: Color {
        QueueColors.onPrimary
    }

    private var fillColor: Color {
        isDestructive ? QueueColors.danger : QueueColors.primary
    }
}

struct QueueSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(QueueTypography.headline(17))
            .foregroundStyle(QueueColors.textPrimary)
            .frame(maxWidth: .infinity, minHeight: QueueSpacing.minTouch)
            .background(
                RoundedRectangle(cornerRadius: QueueSpacing.cornerMinimal, style: .continuous)
                    .fill(QueueColors.surface)
            )
            .opacity(configuration.isPressed ? 0.88 : 1)
    }
}

struct QueueTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding(QueueSpacing.md)
            .background(
                RoundedRectangle(cornerRadius: QueueSpacing.cornerMinimal, style: .continuous)
                    .fill(QueueColors.surface.opacity(0.55))
            )
    }
}
