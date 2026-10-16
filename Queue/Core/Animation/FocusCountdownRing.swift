import SwiftUI

/// Date-anchored progress ring. Remaining fraction is derived from the session, never a tick counter.
struct FocusCountdownRing: View {
    let progress: Double
    let isExpired: Bool
    let isPaused: Bool
    let reduceMotion: Bool

    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(QueueColors.ivory.opacity(0.12), lineWidth: 6)

            Circle()
                .trim(from: 0, to: CGFloat(min(1, max(0, progress))))
                .stroke(
                    AngularGradient(
                        colors: ringColors,
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 6, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : QueueMotion.standard, value: progress)

            if isExpired && !reduceMotion {
                Circle()
                    .stroke(QueueColors.reward.opacity(0.35), lineWidth: 6)
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

    private var ringColors: [Color] {
        if isExpired {
            return [QueueColors.reward.opacity(0.85), QueueColors.reward]
        }
        if isPaused {
            return [QueueColors.ivory.opacity(0.35), QueueColors.ivory.opacity(0.55)]
        }
        return [QueueColors.sage.opacity(0.75), QueueColors.reward.opacity(0.9)]
    }
}
