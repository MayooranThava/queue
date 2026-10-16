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

    var body: some View {
        TimelineView(.animation(minimumInterval: shouldDriveMotion ? 1.0 / 30.0 : nil, paused: !shouldDriveMotion)) { timeline in
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                drawCompanion(
                    context: context,
                    center: center,
                    size: size,
                    time: timeline.date.timeIntervalSinceReferenceDate
                )
            }
        }
    }

    private var shouldDriveMotion: Bool {
        switch state {
        case .idle, .preparing, .working, .celebrating, .levelUp, .paused, .timerExpired, .completed:
            return true
        }
    }

    private func drawCompanion(context: GraphicsContext, center: CGPoint, size: CGSize, time: TimeInterval) {
        var context = context
        let scale = min(size.width, size.height) / 80

        let breathAmp: CGFloat = {
            switch state {
            case .working: return 1.2
            case .paused, .timerExpired: return 0.7
            case .celebrating, .levelUp: return 2.2
            case .preparing: return 1.0
            default: return 1.5
            }
        }()
        let breathSpeed: Double = state == .working ? 1.35 : 1.1
        let breath = CGFloat(sin(time * breathSpeed)) * breathAmp * scale

        let prepBob = state == .preparing ? CGFloat(sin(time * 2.2)) * 1.2 * scale : 0
        let celebrateHop = (state == .celebrating || state == .levelUp)
            ? abs(CGFloat(sin(time * 5.5))) * 3.5 * scale
            : 0
        let vertical = breath + prepBob - celebrateHop

        // Soft floor shadow
        context.fill(
            Path(ellipseIn: CGRect(
                x: center.x - 22 * scale,
                y: center.y + 20 * scale,
                width: 44 * scale,
                height: 8 * scale
            )),
            with: .color(QueueColors.ink.opacity(0.12))
        )

        // Desk
        let desk = Path(roundedRect: CGRect(
            x: center.x - 30 * scale,
            y: center.y + 14 * scale,
            width: 60 * scale,
            height: 8 * scale
        ), cornerRadius: 3 * scale)
        context.fill(desk, with: .color(QueueColors.sageDeep.opacity(0.55)))

        // Laptop base + screen
        let typePulse = state == .working ? CGFloat(sin(time * 10)) * 1.2 * scale : 0
        let laptopY = center.y + 6 * scale + typePulse * 0.25
        let laptopBase = Path(roundedRect: CGRect(
            x: center.x - 14 * scale,
            y: laptopY + 4 * scale,
            width: 28 * scale,
            height: 6 * scale
        ), cornerRadius: 2 * scale)
        context.fill(laptopBase, with: .color(QueueColors.charcoal.opacity(0.85)))

        let screenGlow: Double = {
            switch state {
            case .working: return 0.35 + 0.25 * (0.5 + 0.5 * sin(time * 6))
            case .paused: return 0.18
            case .preparing: return 0.22 + 0.08 * sin(time * 3)
            case .timerExpired: return 0.12
            default: return 0.2
            }
        }()
        let screen = Path(roundedRect: CGRect(
            x: center.x - 12 * scale,
            y: laptopY - 6 * scale,
            width: 24 * scale,
            height: 12 * scale
        ), cornerRadius: 1.5 * scale)
        context.fill(screen, with: .color(QueueColors.charcoal.opacity(0.9)))
        context.fill(
            Path(roundedRect: CGRect(
                x: center.x - 10 * scale,
                y: laptopY - 4.5 * scale,
                width: 20 * scale,
                height: 8 * scale
            ), cornerRadius: 1 * scale),
            with: .color(QueueColors.reward.opacity(screenGlow))
        )

        // Body
        let bodyRect = CGRect(
            x: center.x - 18 * scale,
            y: center.y - 10 * scale + vertical,
            width: 36 * scale,
            height: 28 * scale
        )
        context.fill(Path(ellipseIn: bodyRect), with: .color(QueueColors.sage))

        // Arms / typing hands (working only)
        if state == .working {
            let handY = laptopY + 2 * scale + typePulse
            context.fill(
                Path(ellipseIn: CGRect(
                    x: center.x - 10 * scale,
                    y: handY,
                    width: 5 * scale,
                    height: 4 * scale
                )),
                with: .color(QueueColors.sage.opacity(0.95))
            )
            context.fill(
                Path(ellipseIn: CGRect(
                    x: center.x + 5 * scale,
                    y: handY - typePulse * 0.4,
                    width: 5 * scale,
                    height: 4 * scale
                )),
                with: .color(QueueColors.sage.opacity(0.95))
            )
        }

        // Head
        let lean: CGFloat = {
            switch state {
            case .working: return CGFloat(sin(time * 0.7)) * 0.8 * scale
            case .paused: return -1.5 * scale
            case .timerExpired: return 1.2 * scale
            default: return 0
            }
        }()
        let headRect = CGRect(
            x: center.x - 12 * scale + lean,
            y: bodyRect.minY - 16 * scale,
            width: 24 * scale,
            height: 22 * scale
        )
        context.fill(Path(ellipseIn: headRect), with: .color(QueueColors.sage.opacity(0.95)))

        // Eyes — blink on idle/working; softer on expired
        let eyeY = headRect.midY - 1 * scale
        let blinkGate = sin(time * 2.7)
        let blinking = (state == .idle || state == .working || state == .preparing) && blinkGate > 0.92
        let eyeOpen: CGFloat = {
            if state == .timerExpired { return 1.15 }
            if state == .paused { return 1.6 }
            return blinking ? 0.45 : 2.1
        }()
        let eyeHeight = eyeOpen * scale
        context.fill(
            Path(ellipseIn: CGRect(x: headRect.midX - 6 * scale, y: eyeY, width: 2.5 * scale, height: eyeHeight)),
            with: .color(QueueColors.ink)
        )
        context.fill(
            Path(ellipseIn: CGRect(x: headRect.midX + 3.5 * scale, y: eyeY, width: 2.5 * scale, height: eyeHeight)),
            with: .color(QueueColors.ink)
        )

        // Soft smile when celebrating
        if state == .celebrating || state == .levelUp || state == .completed {
            var smile = Path()
            smile.addArc(
                center: CGPoint(x: headRect.midX, y: headRect.midY + 4 * scale),
                radius: 4 * scale,
                startAngle: .degrees(20),
                endAngle: .degrees(160),
                clockwise: false
            )
            context.stroke(
                smile,
                with: .color(QueueColors.ink.opacity(0.55)),
                style: StrokeStyle(lineWidth: 1.2 * scale, lineCap: .round)
            )
        }

        // Level-up badge
        if state == .levelUp {
            let badgeCenter = CGPoint(x: center.x + 22 * scale, y: center.y - 26 * scale + CGFloat(sin(time * 4)) * scale)
            context.fill(
                Path(ellipseIn: CGRect(x: badgeCenter.x - 7 * scale, y: badgeCenter.y - 7 * scale, width: 14 * scale, height: 14 * scale)),
                with: .color(QueueColors.reward)
            )
            context.fill(
                Path(ellipseIn: CGRect(x: badgeCenter.x - 3 * scale, y: badgeCenter.y - 3 * scale, width: 6 * scale, height: 6 * scale)),
                with: .color(QueueColors.ivory.opacity(0.9))
            )
        }

        // Restrained sparkles / confetti
        if state == .celebrating || state == .levelUp || state == .completed {
            drawSparkles(context: &context, center: center, scale: scale, time: time, richer: state == .levelUp)
        }

        // Thought bubble for timer expired (calm, not disappointed)
        if state == .timerExpired {
            let bx = center.x + 20 * scale
            let by = center.y - 22 * scale
            context.fill(
                Path(ellipseIn: CGRect(x: bx, y: by, width: 14 * scale, height: 10 * scale)),
                with: .color(QueueColors.ivory.opacity(0.14))
            )
            context.fill(
                Path(ellipseIn: CGRect(x: bx + 2 * scale, y: by + 10 * scale, width: 3 * scale, height: 3 * scale)),
                with: .color(QueueColors.ivory.opacity(0.12))
            )
        }
    }

    private func drawSparkles(
        context: inout GraphicsContext,
        center: CGPoint,
        scale: CGFloat,
        time: TimeInterval,
        richer: Bool
    ) {
        let count = richer ? 8 : 4
        for i in 0..<count {
            let phase = time * (2.8 + Double(i) * 0.35) + Double(i)
            let orbit = 18 + Double(i % 3) * 6
            let x = center.x + CGFloat(cos(phase) * orbit) * scale
            let y = center.y - 18 * scale + CGFloat(sin(phase * 1.3) * 10) * scale - CGFloat((phase * 4).truncatingRemainder(dividingBy: 8)) * scale
            let alpha = 0.35 + 0.4 * abs(sin(phase * 2))
            let size = (richer ? 3.2 : 2.6) * scale * (i % 2 == 0 ? 1.0 : 0.7)
            context.fill(
                Path(ellipseIn: CGRect(x: x, y: y, width: size, height: size)),
                with: .color(QueueColors.reward.opacity(alpha))
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
            if state == .levelUp {
                Circle()
                    .fill(QueueColors.reward)
                    .frame(width: 10, height: 10)
                    .offset(x: 26, y: -28)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
