import SwiftUI
import QueueCore

/// Date-anchored progress ring. Remaining fraction is derived from the session, never a tick counter.
struct FocusCountdownRing: View {
    let progress: Double
    let isExpired: Bool
    let isPaused: Bool
    let reduceMotion: Bool
    /// Focus uses a heavier stroke. The stack's live card passes a thinner one.
    var lineWidth: CGFloat = 6

    @Environment(\.queueTheme) private var queueTheme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(color(.textPrimary).opacity(0.18), lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: CGFloat(min(1, max(0, progress))))
                .stroke(
                    AngularGradient(
                        colors: ringColors,
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : QueueMotion.standard, value: progress)

            if isExpired && !reduceMotion {
                Circle()
                    .stroke(progressColor.opacity(0.35), lineWidth: lineWidth)
                    .scaleEffect(pulse ? 1.04 : 1.0)
                    .opacity(pulse ? 0.35 : 0.7)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                            pulse = true
                        }
                    }
            }
        }
        .accessibilityHidden(true)
    }

    /// Honey reads on the dark column. Light surfaces use primary so the stroke stays visible.
    private var progressColor: Color {
        color(colorScheme == .dark ? .accent : .primary)
    }

    private func color(_ role: QueueColorRole) -> Color {
        QueueColors.concrete(
            role,
            theme: queueTheme,
            scheme: colorScheme,
            increasedContrast: contrast == .increased
        )
    }

    private var ringColors: [Color] {
        if isPaused {
            let paused = color(.textSecondary)
            return [paused, paused]
        }
        return [progressColor.opacity(0.85), progressColor]
    }
}
