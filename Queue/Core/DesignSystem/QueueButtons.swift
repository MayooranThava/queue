import SwiftUI

struct QueuePrimaryButtonStyle: ButtonStyle {
    var isDestructive: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(QueueTypography.headline(17))
            .foregroundStyle(isDestructive ? Color.white : QueueColors.ivory)
            .frame(maxWidth: .infinity, minHeight: QueueSpacing.minTouch)
            .background(
                RoundedRectangle(cornerRadius: QueueSpacing.cornerMinimal, style: .continuous)
                    .fill(isDestructive ? QueueColors.dangerSoft : QueueColors.ink)
            )
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
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
