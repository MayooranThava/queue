import SwiftUI

enum CompanionVisualState: String, Sendable {
    case idle
    case preparing
    case working
    case paused
    case completed
    case celebrating
    case levelUp
    case timerExpired
}

/// Resolves Rive (future) → SwiftUI vector → static (Reduce Motion).
struct CompanionAnimationView: View {
    let state: CompanionVisualState
    let reduceMotion: Bool

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.scenePhase) private var scenePhase

    private var shouldAnimate: Bool {
        !reduceMotion && !systemReduceMotion && scenePhase == .active
    }

    var body: some View {
        Group {
            if shouldAnimate {
                NativeCompanionView(state: state)
            } else {
                StaticCompanionView(state: state)
            }
        }
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        switch state {
        case .idle: return "Companion resting"
        case .preparing: return "Companion getting ready"
        case .working: return "Companion focusing with you"
        case .paused: return "Companion paused"
        case .completed, .celebrating: return "Companion celebrating"
        case .levelUp: return "Companion celebrating a level up"
        case .timerExpired: return "Companion waiting thoughtfully"
        }
    }
}

struct NativeCompanionView: View {
    let state: CompanionVisualState
    @State private var blink = false
    @State private var breathe = false
    @State private var typeOffset: CGFloat = 0

    var body: some View {
        TimelineView(.animation(minimumInterval: shouldDriveMotion ? 1.0 / 30.0 : nil, paused: !shouldDriveMotion)) { timeline in
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                drawCompanion(context: context, center: center, size: size, time: timeline.date.timeIntervalSinceReferenceDate)
            }
        }
        .onAppear { startLoops() }
        .onChange(of: state) { _, _ in startLoops() }
    }

    private var shouldDriveMotion: Bool {
        switch state {
        case .idle, .preparing, .working, .celebrating, .levelUp: return true
        case .paused, .completed, .timerExpired: return false
        }
    }

    private func startLoops() {
        withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
            breathe = true
        }
        if state == .working {
            withAnimation(.easeInOut(duration: 0.35).repeatForever(autoreverses: true)) {
                typeOffset = 2
            }
        } else {
            typeOffset = 0
        }
    }

    private func drawCompanion(context: GraphicsContext, center: CGPoint, size: CGSize, time: TimeInterval) {
        var context = context
        let scale = min(size.width, size.height) / 80
        let breath = breathe ? CGFloat(sin(time * 1.2)) * 1.5 * scale : 0
        let bodyRect = CGRect(
            x: center.x - 18 * scale,
            y: center.y - 10 * scale + breath,
            width: 36 * scale,
            height: 28 * scale
        )

        // Desk
        let desk = Path(roundedRect: CGRect(
            x: center.x - 30 * scale,
            y: center.y + 14 * scale,
            width: 60 * scale,
            height: 8 * scale
        ), cornerRadius: 3 * scale)
        context.fill(desk, with: .color(QueueColors.sageDeep.opacity(0.55)))

        // Laptop
        let laptopY = center.y + 6 * scale + (state == .working ? typeOffset * scale * 0.3 : 0)
        let laptop = Path(roundedRect: CGRect(
            x: center.x - 14 * scale,
            y: laptopY,
            width: 28 * scale,
            height: 10 * scale
        ), cornerRadius: 2 * scale)
        context.fill(laptop, with: .color(QueueColors.charcoal.opacity(0.85)))

        // Body
        context.fill(
            Path(ellipseIn: bodyRect),
            with: .color(QueueColors.sage)
        )

        // Head
        let headRect = CGRect(
            x: center.x - 12 * scale,
            y: bodyRect.minY - 16 * scale,
            width: 24 * scale,
            height: 22 * scale
        )
        context.fill(Path(ellipseIn: headRect), with: .color(QueueColors.sage.opacity(0.95)))

        // Eyes
        let eyeY = headRect.midY - 1 * scale
        let eyeOpen = state == .idle ? (sin(time * 3) > 0.92 ? 0.5 : 2.0) : 2.0
        let eyeHeight = (state == .timerExpired ? 1.2 : eyeOpen) * scale
        context.fill(
            Path(ellipseIn: CGRect(x: headRect.midX - 6 * scale, y: eyeY, width: 2.5 * scale, height: eyeHeight)),
            with: .color(QueueColors.ink)
        )
        context.fill(
            Path(ellipseIn: CGRect(x: headRect.midX + 3.5 * scale, y: eyeY, width: 2.5 * scale, height: eyeHeight)),
            with: .color(QueueColors.ink)
        )

        // Celebration sparkles
        if state == .celebrating || state == .levelUp || state == .completed {
            let sparkleAlpha = 0.45 + 0.35 * sin(time * 6)
            context.fill(
                Path(ellipseIn: CGRect(x: center.x + 20 * scale, y: center.y - 22 * scale, width: 4 * scale, height: 4 * scale)),
                with: .color(QueueColors.reward.opacity(sparkleAlpha))
            )
            context.fill(
                Path(ellipseIn: CGRect(x: center.x - 24 * scale, y: center.y - 16 * scale, width: 3 * scale, height: 3 * scale)),
                with: .color(QueueColors.reward.opacity(sparkleAlpha * 0.8))
            )
        }
    }
}

struct StaticCompanionView: View {
    let state: CompanionVisualState

    var body: some View {
        ZStack {
            Circle()
                .fill(QueueColors.sage.opacity(0.85))
                .frame(width: 44, height: 44)
                .offset(y: -6)
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(QueueColors.sage)
                .frame(width: 52, height: 36)
                .offset(y: 10)
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(QueueColors.charcoal.opacity(0.8))
                .frame(width: 28, height: 10)
                .offset(y: 18)
            if state == .celebrating || state == .levelUp || state == .completed {
                Circle()
                    .fill(QueueColors.reward)
                    .frame(width: 6, height: 6)
                    .offset(x: 28, y: -20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
