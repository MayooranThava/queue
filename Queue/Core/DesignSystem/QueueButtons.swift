import SwiftUI

struct QueuePrimaryButtonStyle: ButtonStyle {
    var isDestructive: Bool = false
    /// Use on charcoal Focus surfaces where ink-on-charcoal is too low-contrast.
    var onDarkSurface: Bool = false

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
        if isDestructive { return .white }
        return onDarkSurface ? QueueColors.charcoal : QueueColors.ivory
    }

    private var fillColor: Color {
        if isDestructive { return QueueColors.dangerSoft }
        return onDarkSurface ? QueueColors.ivory : QueueColors.ink
    }
}

struct QueueSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(QueueTypography.headline(17))
            .foregroundStyle(QueueColors.primaryText)
            .frame(maxWidth: .infinity, minHeight: QueueSpacing.minTouch)
            .background(
                RoundedRectangle(cornerRadius: QueueSpacing.cornerMinimal, style: .continuous)
                    .fill(QueueColors.secondarySurface)
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
                    .fill(QueueColors.secondarySurface.opacity(0.55))
            )
    }
}
