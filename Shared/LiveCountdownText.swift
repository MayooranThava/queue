import SwiftUI
import QueueCore

/// System-driven countdown that keeps ticking while the app is backgrounded
/// (Home Screen widgets + Live Activities). Falls back to a static clock when paused/expired.
struct LiveCountdownText: View {
    let snapshot: FocusWidgetSnapshot
    let at: Date
    var fontSize: CGFloat = 32
    var weight: Font.Weight = .medium
    var color: Color = QueueColors.dark(.textPrimary)
    var minimumScale: CGFloat = 0.7

    var body: some View {
        Group {
            if snapshot.session.state == .running,
               snapshot.remaining(at: at) > 0,
               let end = snapshot.runningEndDate(at: at) {
                Text(timerInterval: at...end, countsDown: true)
            } else {
                Text(FocusTimerFormatting.clock(snapshot.remaining(at: at)))
            }
        }
        .font(.system(size: fontSize, weight: weight, design: .rounded).monospacedDigit())
        .monospacedDigit()
        .foregroundStyle(color)
        .minimumScaleFactor(minimumScale)
        .lineLimit(1)
        .accessibilityLabel(
            "Time remaining \(FocusTimerFormatting.spoken(snapshot.remaining(at: at)))"
        )
    }
}
