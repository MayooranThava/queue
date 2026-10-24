import SwiftUI
import QueueCore

/// Date-anchored progress ring. Remaining fraction is derived from the session, never a tick counter.
struct FocusCountdownRing: View {
    let progress: Double
    let isExpired: Bool
    let isPaused: Bool
    let reduceMotion: Bool
    /// The focus screen uses 10pt. The stack's live card passes a thinner stroke.
    var lineWidth: CGFloat = 6

    @Environment(\.queueTheme) private var queueTheme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var pulseScale: CGFloat = 1
    @State private var didPulse = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(
                    trackColor,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )

            Circle()
                .trim(from: 0, to: displayedFill)
                .stroke(
                    strokeColor,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : QueueMotion.standard, value: displayedFill)
                .scaleEffect(pulseScale)
        }
        .padding(lineWidth / 2)
        .accessibilityHidden(true)
        .onAppear { startPulseIfNeeded() }
        .onChange(of: isExpired) { _, expired in
            if expired {
                startPulseIfNeeded()
            } else {
                didPulse = false
                pulseScale = 1
            }
        }
    }

    /// Time's up is a full ring. Otherwise the arc shrinks with the remaining fraction.
    private var displayedFill: CGFloat {
        CGFloat(FocusRingMetrics.ringFill(progress: progress, isTimeUp: isExpired))
    }

    private var trackColor: Color {
        color(.textPrimary).opacity(FocusRingMetrics.trackOpacity)
    }

    /// Dark time's up is honey. Light time's up, and every running ring, stay on primary.
    private var strokeColor: Color {
        switch FocusRingMetrics.stroke(
            isTimeUp: isExpired,
            isPaused: isPaused,
            isDark: colorScheme == .dark
        ) {
        case .primary:
            return color(.primary)
        case .accent:
            return color(.accent)
        case .paused:
            return color(.textSecondary)
        }
    }

    private func color(_ role: QueueColorRole) -> Color {
        QueueColors.concrete(
            role,
            theme: queueTheme,
            scheme: colorScheme,
            increasedContrast: contrast == .increased
        )
    }

    /// One slow breath of the full ring, then it rests. Reduce Motion stays still.
    private func startPulseIfNeeded() {
        guard isExpired, !reduceMotion, !didPulse else { return }
        didPulse = true
        let duration = FocusRingMetrics.timeUpPulseDuration
        withAnimation(.easeInOut(duration: duration)) {
            pulseScale = 1.04
        } completion: {
            withAnimation(.easeInOut(duration: duration)) {
                pulseScale = 1
            }
        }
    }
}
