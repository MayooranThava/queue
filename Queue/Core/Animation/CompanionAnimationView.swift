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
/// Visual language follows the desk/laptop companion storyboard: lamp, typing, props per state.
struct CompanionAnimationView: View {
    let state: CompanionVisualState
    let reduceMotion: Bool
    /// Smaller Queue-card footprint still shows laptop + typing, not just a blinking blob.
    var compact: Bool = false

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.scenePhase) private var scenePhase

    private var shouldAnimate: Bool {
        !reduceMotion && !systemReduceMotion && scenePhase == .active
    }

    var body: some View {
        Group {
            if shouldAnimate {
                NativeCompanionView(state: state, compact: compact)
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
    var compact: Bool = false

    var body: some View {
        TimelineView(.animation(minimumInterval: shouldDriveMotion ? 1.0 / 30.0 : nil, paused: !shouldDriveMotion)) { timeline in
            Canvas { context, size in
                drawScene(
                    context: context,
                    size: size,
                    time: timeline.date.timeIntervalSinceReferenceDate
                )
            }
        }
    }

    private var shouldDriveMotion: Bool { true }

    private func drawScene(context: GraphicsContext, size: CGSize, time: TimeInterval) {
        var context = context
        let scale = min(size.width, size.height) / (compact ? 72 : 100)
        let center = CGPoint(x: size.width / 2, y: size.height / 2 + (compact ? 2 : 4) * scale)

        let breathSpeed: Double = {
            switch state {
            case .working: return 1.45
            case .paused, .timerExpired: return 0.85
            case .celebrating, .levelUp: return 2.2
            default: return 1.15
            }
        }()
        let breathAmp: CGFloat = {
            switch state {
            case .working: return 1.4
            case .paused: return 0.55
            case .celebrating, .levelUp: return 2.4
            case .preparing: return 1.1
            default: return 1.3
            }
        }()
        let breath = CGFloat(sin(time * breathSpeed)) * breathAmp * scale
        let prepBob = state == .preparing ? CGFloat(sin(time * 2.4)) * 1.1 * scale : 0
        let celebrateHop = (state == .celebrating || state == .levelUp)
            ? abs(CGFloat(sin(time * 5.2))) * 4.0 * scale
            : 0
        let bodyY = breath + prepBob - celebrateHop

        // Deep-focus beat inside working: headphones ~every other stretch.
        let deepFocus = state == .working && sin(time * 0.22) > 0.25

        // Soft floor shadow
        context.fill(
            Path(ellipseIn: CGRect(
                x: center.x - 26 * scale,
                y: center.y + 26 * scale,
                width: 52 * scale,
                height: 9 * scale
            )),
            with: .color(QueueColors.ink.opacity(0.16))
        )

        // Warm wooden desk (storyboard anchor)
        let deskRect = CGRect(
            x: center.x - 34 * scale,
            y: center.y + 16 * scale,
            width: 68 * scale,
            height: 10 * scale
        )
        context.fill(
            Path(roundedRect: deskRect, cornerRadius: 3.5 * scale),
            with: .color(Color(red: 0.42, green: 0.32, blue: 0.24).opacity(0.92))
        )
        context.fill(
            Path(roundedRect: CGRect(
                x: deskRect.minX + 2 * scale,
                y: deskRect.minY + 1.5 * scale,
                width: deskRect.width - 4 * scale,
                height: 2.2 * scale
            ), cornerRadius: 1 * scale),
            with: .color(Color(red: 0.55, green: 0.42, blue: 0.30).opacity(0.55))
        )

        // Plant (right) — present in most calm states
        if state != .celebrating && state != .levelUp {
            drawPlant(context: &context, at: CGPoint(x: center.x + 26 * scale, y: deskRect.minY), scale: scale)
        }

        // Body sits behind the laptop (storyboard order)
        let lean: CGFloat = {
            switch state {
            case .working: return CGFloat(sin(time * 0.85)) * 1.1 * scale
            case .paused: return 0
            case .timerExpired: return CGFloat(sin(time * 3.2)) * 0.6 * scale
            case .preparing: return -0.4 * scale
            default: return 0
            }
        }()
        let slumped = state == .paused
        let bodyRect = CGRect(
            x: center.x - 17 * scale + lean * 0.35,
            y: center.y - 8 * scale + bodyY + (slumped ? 4 * scale : 0),
            width: 34 * scale,
            height: 30 * scale
        )
        context.fill(Path(ellipseIn: bodyRect), with: .color(QueueColors.sage))

        let headRect = CGRect(
            x: center.x - 12 * scale + lean,
            y: bodyRect.minY - (slumped ? 8 : 15) * scale,
            width: 24 * scale,
            height: 22 * scale
        )
        context.fill(Path(ellipseIn: headRect), with: .color(QueueColors.sage.opacity(0.97)))

        drawFace(context: &context, headRect: headRect, scale: scale, time: time, deepFocus: deepFocus)

        // Laptop in front of torso
        let typePulse = state == .working && !deepFocus ? CGFloat(sin(time * 11.5)) : 0
        let laptopOrigin = CGPoint(x: center.x, y: center.y + 4 * scale)
        drawLaptop(
            context: &context,
            origin: laptopOrigin,
            scale: scale,
            time: time,
            glow: laptopGlow(time: time)
        )

        // Desk lamp when actively working / deep focus
        if state == .working {
            drawLamp(
                context: &context,
                at: CGPoint(x: center.x - 24 * scale, y: deskRect.minY),
                scale: scale,
                time: time,
                on: true
            )
        }

        // State props + arms on top
        drawArmsAndProps(
            context: &context,
            center: center,
            headRect: headRect,
            bodyRect: bodyRect,
            deskY: deskRect.minY,
            laptopOrigin: laptopOrigin,
            scale: scale,
            time: time,
            typePulse: typePulse,
            deepFocus: deepFocus
        )

        if state == .celebrating || state == .levelUp || state == .completed {
            drawSparkles(context: &context, center: center, scale: scale, time: time, richer: state == .levelUp)
        }
    }

    private func laptopGlow(time: TimeInterval) -> Double {
        switch state {
        case .working: return 0.45 + 0.28 * (0.5 + 0.5 * sin(time * 5.5))
        case .paused: return 0.12
        case .preparing: return 0.2 + 0.08 * sin(time * 2.8)
        case .timerExpired: return 0.1
        case .idle: return 0.18
        default: return 0.22
        }
    }

    private func drawFace(
        context: inout GraphicsContext,
        headRect: CGRect,
        scale: CGFloat,
        time: TimeInterval,
        deepFocus: Bool
    ) {
        let eyeY = headRect.midY - 1.2 * scale
        let blinkGate = sin(time * 2.55)
        let blinking = (state == .idle || state == .working || state == .preparing) && blinkGate > 0.93

        enum EyeStyle { case open, closed, squint, sleepy }
        let style: EyeStyle = {
            if state == .paused { return .sleepy }
            if state == .timerExpired { return .squint }
            if deepFocus { return .closed }
            if state == .preparing && sin(time * 1.4) > 0.6 { return .closed }
            if blinking { return .closed }
            return .open
        }()

        let eyeHeight: CGFloat = {
            switch style {
            case .open: return 2.3 * scale
            case .closed: return 0.55 * scale
            case .squint: return 1.1 * scale
            case .sleepy: return 0.7 * scale
            }
        }()

        let leftEye = CGRect(x: headRect.midX - 6.2 * scale, y: eyeY, width: 2.6 * scale, height: eyeHeight)
        let rightEye = CGRect(x: headRect.midX + 3.6 * scale, y: eyeY, width: 2.6 * scale, height: eyeHeight)
        context.fill(Path(ellipseIn: leftEye), with: .color(QueueColors.ink))
        context.fill(Path(ellipseIn: rightEye), with: .color(QueueColors.ink))

        // Mouth
        switch state {
        case .celebrating, .levelUp, .completed:
            var smile = Path()
            smile.addArc(
                center: CGPoint(x: headRect.midX, y: headRect.midY + 4.5 * scale),
                radius: 4.2 * scale,
                startAngle: .degrees(18),
                endAngle: .degrees(162),
                clockwise: false
            )
            context.stroke(
                smile,
                with: .color(QueueColors.ink.opacity(0.6)),
                style: StrokeStyle(lineWidth: 1.3 * scale, lineCap: .round)
            )
        case .working where !deepFocus, .idle, .preparing:
            context.stroke(
                Path { path in
                    path.move(to: CGPoint(x: headRect.midX - 2.2 * scale, y: headRect.midY + 5 * scale))
                    path.addLine(to: CGPoint(x: headRect.midX + 2.2 * scale, y: headRect.midY + 5 * scale))
                },
                with: .color(QueueColors.ink.opacity(0.45)),
                style: StrokeStyle(lineWidth: 1.1 * scale, lineCap: .round)
            )
        default:
            break
        }

        if deepFocus {
            // Closed content eyes as short arcs
            context.stroke(
                Path { path in
                    path.addArc(
                        center: CGPoint(x: leftEye.midX, y: eyeY + 0.4 * scale),
                        radius: 1.6 * scale,
                        startAngle: .degrees(200),
                        endAngle: .degrees(340),
                        clockwise: false
                    )
                },
                with: .color(QueueColors.ink.opacity(0.7)),
                style: StrokeStyle(lineWidth: 1.1 * scale, lineCap: .round)
            )
            context.stroke(
                Path { path in
                    path.addArc(
                        center: CGPoint(x: rightEye.midX, y: eyeY + 0.4 * scale),
                        radius: 1.6 * scale,
                        startAngle: .degrees(200),
                        endAngle: .degrees(340),
                        clockwise: false
                    )
                },
                with: .color(QueueColors.ink.opacity(0.7)),
                style: StrokeStyle(lineWidth: 1.1 * scale, lineCap: .round)
            )
        }
    }

    private func drawLaptop(
        context: inout GraphicsContext,
        origin: CGPoint,
        scale: CGFloat,
        time: TimeInterval,
        glow: Double
    ) {
        let base = Path(roundedRect: CGRect(
            x: origin.x - 15 * scale,
            y: origin.y + 6 * scale,
            width: 30 * scale,
            height: 5.5 * scale
        ), cornerRadius: 1.8 * scale)
        context.fill(base, with: .color(QueueColors.charcoal.opacity(0.92)))

        let screen = Path(roundedRect: CGRect(
            x: origin.x - 13 * scale,
            y: origin.y - 8 * scale,
            width: 26 * scale,
            height: 15 * scale
        ), cornerRadius: 2 * scale)
        context.fill(screen, with: .color(QueueColors.charcoal.opacity(0.95)))

        let display = Path(roundedRect: CGRect(
            x: origin.x - 11 * scale,
            y: origin.y - 6.2 * scale,
            width: 22 * scale,
            height: 10.5 * scale
        ), cornerRadius: 1.2 * scale)
        context.fill(display, with: .color(QueueColors.reward.opacity(glow)))

        // Leaf logo on lid / bezel
        let leaf = Path(ellipseIn: CGRect(
            x: origin.x - 2.2 * scale,
            y: origin.y - 1.5 * scale,
            width: 4.4 * scale,
            height: 3.2 * scale
        ))
        context.fill(leaf, with: .color(QueueColors.sage.opacity(0.85)))
    }

    private func drawLamp(
        context: inout GraphicsContext,
        at point: CGPoint,
        scale: CGFloat,
        time: TimeInterval,
        on: Bool
    ) {
        let baseY = point.y
        context.fill(
            Path(ellipseIn: CGRect(x: point.x - 3 * scale, y: baseY - 2 * scale, width: 6 * scale, height: 3 * scale)),
            with: .color(QueueColors.charcoal.opacity(0.75))
        )
        var arm = Path()
        arm.move(to: CGPoint(x: point.x, y: baseY - 2 * scale))
        arm.addLine(to: CGPoint(x: point.x - 1 * scale, y: baseY - 16 * scale))
        context.stroke(arm, with: .color(QueueColors.charcoal.opacity(0.8)), style: StrokeStyle(lineWidth: 1.4 * scale, lineCap: .round))

        let shade = Path(ellipseIn: CGRect(
            x: point.x - 6 * scale,
            y: baseY - 20 * scale,
            width: 10 * scale,
            height: 6 * scale
        ))
        context.fill(shade, with: .color(Color(red: 0.85, green: 0.78, blue: 0.45).opacity(0.9)))

        if on {
            let pulse = 0.12 + 0.06 * sin(time * 3.2)
            context.fill(
                Path(ellipseIn: CGRect(
                    x: point.x - 10 * scale,
                    y: baseY - 8 * scale,
                    width: 22 * scale,
                    height: 14 * scale
                )),
                with: .color(Color(red: 1.0, green: 0.92, blue: 0.55).opacity(pulse))
            )
        }
    }

    private func drawPlant(context: inout GraphicsContext, at point: CGPoint, scale: CGFloat) {
        context.fill(
            Path(roundedRect: CGRect(x: point.x - 3 * scale, y: point.y - 5 * scale, width: 6 * scale, height: 5 * scale), cornerRadius: 1 * scale),
            with: .color(Color(red: 0.55, green: 0.42, blue: 0.32).opacity(0.9))
        )
        context.fill(
            Path(ellipseIn: CGRect(x: point.x - 4.5 * scale, y: point.y - 12 * scale, width: 5 * scale, height: 7 * scale)),
            with: .color(QueueColors.sageDeep.opacity(0.85))
        )
        context.fill(
            Path(ellipseIn: CGRect(x: point.x - 0.5 * scale, y: point.y - 13 * scale, width: 5 * scale, height: 7 * scale)),
            with: .color(QueueColors.sage.opacity(0.8))
        )
    }

    private func drawArmsAndProps(
        context: inout GraphicsContext,
        center: CGPoint,
        headRect: CGRect,
        bodyRect: CGRect,
        deskY: CGFloat,
        laptopOrigin: CGPoint,
        scale: CGFloat,
        time: TimeInterval,
        typePulse: CGFloat,
        deepFocus: Bool
    ) {
        switch state {
        case .working:
            if deepFocus {
                // Headphones + restful hands on the deck
                let band = Path { path in
                    path.addArc(
                        center: CGPoint(x: headRect.midX, y: headRect.midY - 2 * scale),
                        radius: 13 * scale,
                        startAngle: .degrees(200),
                        endAngle: .degrees(340),
                        clockwise: false
                    )
                }
                context.stroke(
                    band,
                    with: .color(QueueColors.sageDeep.opacity(0.95)),
                    style: StrokeStyle(lineWidth: 2.2 * scale, lineCap: .round)
                )
                context.fill(
                    Path(ellipseIn: CGRect(x: headRect.minX - 3 * scale, y: headRect.midY - 3 * scale, width: 5 * scale, height: 7 * scale)),
                    with: .color(QueueColors.sageDeep)
                )
                context.fill(
                    Path(ellipseIn: CGRect(x: headRect.maxX - 2 * scale, y: headRect.midY - 3 * scale, width: 5 * scale, height: 7 * scale)),
                    with: .color(QueueColors.sageDeep)
                )
                let noteAlpha = 0.35 + 0.25 * abs(sin(time * 2.4))
                context.fill(
                    Path(ellipseIn: CGRect(
                        x: headRect.maxX + 4 * scale,
                        y: headRect.minY - 4 * scale + CGFloat(sin(time * 2)) * 2 * scale,
                        width: 3 * scale,
                        height: 3 * scale
                    )),
                    with: .color(QueueColors.reward.opacity(noteAlpha))
                )
                let restY = laptopOrigin.y + 5.5 * scale
                drawHand(context: &context, at: CGPoint(x: center.x - 8 * scale, y: restY), scale: scale)
                drawHand(context: &context, at: CGPoint(x: center.x + 4 * scale, y: restY), scale: scale)
            } else {
                // Typing hands — clearly above the keyboard, alternating
                let leftY = laptopOrigin.y + 5 * scale + typePulse * 1.6 * scale
                let rightY = laptopOrigin.y + 5 * scale - typePulse * 1.6 * scale
                drawHand(context: &context, at: CGPoint(x: center.x - 8 * scale, y: leftY), scale: scale)
                drawHand(context: &context, at: CGPoint(x: center.x + 4 * scale, y: rightY), scale: scale)

                context.stroke(
                    Path { path in
                        path.move(to: CGPoint(x: bodyRect.minX + 6 * scale, y: bodyRect.midY + 4 * scale))
                        path.addLine(to: CGPoint(x: center.x - 6 * scale, y: leftY + 1 * scale))
                    },
                    with: .color(QueueColors.sage.opacity(0.9)),
                    style: StrokeStyle(lineWidth: 3.2 * scale, lineCap: .round)
                )
                context.stroke(
                    Path { path in
                        path.move(to: CGPoint(x: bodyRect.maxX - 6 * scale, y: bodyRect.midY + 4 * scale))
                        path.addLine(to: CGPoint(x: center.x + 6 * scale, y: rightY + 1 * scale))
                    },
                    with: .color(QueueColors.sage.opacity(0.9)),
                    style: StrokeStyle(lineWidth: 3.2 * scale, lineCap: .round)
                )
            }

        case .preparing:
            // Mug in hands
            let mug = CGRect(x: center.x - 5 * scale, y: deskY - 10 * scale, width: 10 * scale, height: 9 * scale)
            context.fill(Path(roundedRect: mug, cornerRadius: 2 * scale), with: .color(QueueColors.sageDeep.opacity(0.9)))
            context.fill(
                Path(ellipseIn: CGRect(x: mug.midX - 3 * scale, y: mug.minY - 1.5 * scale, width: 6 * scale, height: 3 * scale)),
                with: .color(QueueColors.sage.opacity(0.5))
            )
            // Steam
            for i in 0..<2 {
                let sx = mug.midX + CGFloat(i * 3 - 1) * scale
                let sy = mug.minY - 4 * scale - CGFloat(sin(time * 3 + Double(i))) * 2 * scale
                context.stroke(
                    Path { path in
                        path.move(to: CGPoint(x: sx, y: sy + 4 * scale))
                        path.addQuadCurve(
                            to: CGPoint(x: sx + 1.5 * scale, y: sy),
                            control: CGPoint(x: sx - 2 * scale, y: sy + 2 * scale)
                        )
                    },
                    with: .color(QueueColors.ivory.opacity(0.35)),
                    style: StrokeStyle(lineWidth: 1.1 * scale, lineCap: .round)
                )
            }
            drawHand(context: &context, at: CGPoint(x: mug.minX - 2 * scale, y: mug.midY), scale: scale)
            drawHand(context: &context, at: CGPoint(x: mug.maxX - 1 * scale, y: mug.midY), scale: scale)

        case .paused:
            // Head resting — floating Z marks
            let zAlpha = 0.4 + 0.3 * abs(sin(time * 1.8))
            for (index, offset) in [(0.0, 0.0), (5.0, -5.0), (9.0, -10.0)].enumerated() {
                let zx = headRect.maxX + CGFloat(offset.0) * scale
                let zy = headRect.minY + CGFloat(offset.1) * scale
                let size = (3.5 + CGFloat(index) * 0.8) * scale
                var zee = Path()
                zee.move(to: CGPoint(x: zx, y: zy))
                zee.addLine(to: CGPoint(x: zx + size, y: zy))
                zee.addLine(to: CGPoint(x: zx, y: zy + size))
                zee.addLine(to: CGPoint(x: zx + size, y: zy + size))
                context.stroke(
                    zee,
                    with: .color(QueueColors.ivory.opacity(zAlpha)),
                    style: StrokeStyle(lineWidth: 1.1 * scale, lineCap: .round, lineJoin: .round)
                )
            }

        case .timerExpired:
            // Thought scribble + empty hourglass
            let bx = headRect.maxX + 2 * scale
            let by = headRect.minY - 6 * scale
            context.fill(
                Path(ellipseIn: CGRect(x: bx, y: by, width: 16 * scale, height: 12 * scale)),
                with: .color(QueueColors.ivory.opacity(0.14))
            )
            context.stroke(
                Path { path in
                    path.move(to: CGPoint(x: bx + 4 * scale, y: by + 6 * scale))
                    path.addCurve(
                        to: CGPoint(x: bx + 12 * scale, y: by + 6 * scale),
                        control1: CGPoint(x: bx + 6 * scale, y: by + 2 * scale),
                        control2: CGPoint(x: bx + 10 * scale, y: by + 10 * scale)
                    )
                },
                with: .color(QueueColors.ivory.opacity(0.55)),
                style: StrokeStyle(lineWidth: 1.2 * scale, lineCap: .round)
            )
            drawHourglass(context: &context, at: CGPoint(x: center.x + 22 * scale, y: deskY - 8 * scale), scale: scale, empty: true)

        case .idle:
            // Waiting ellipsis bubble
            let bx = headRect.maxX + 1 * scale
            let by = headRect.minY - 8 * scale
            context.fill(
                Path(ellipseIn: CGRect(x: bx, y: by, width: 16 * scale, height: 11 * scale)),
                with: .color(QueueColors.ivory.opacity(0.12))
            )
            for i in 0..<3 {
                let pulse = 0.35 + 0.35 * abs(sin(time * 2.5 + Double(i) * 0.7))
                context.fill(
                    Path(ellipseIn: CGRect(
                        x: bx + CGFloat(3 + i * 4) * scale,
                        y: by + 4 * scale,
                        width: 2.2 * scale,
                        height: 2.2 * scale
                    )),
                    with: .color(QueueColors.ivory.opacity(pulse))
                )
            }

        case .celebrating, .completed:
            // Arms up
            context.stroke(
                Path { path in
                    path.move(to: CGPoint(x: bodyRect.minX + 4 * scale, y: bodyRect.midY))
                    path.addLine(to: CGPoint(x: bodyRect.minX - 6 * scale, y: headRect.minY - 2 * scale))
                },
                with: .color(QueueColors.sage),
                style: StrokeStyle(lineWidth: 3.4 * scale, lineCap: .round)
            )
            context.stroke(
                Path { path in
                    path.move(to: CGPoint(x: bodyRect.maxX - 4 * scale, y: bodyRect.midY))
                    path.addLine(to: CGPoint(x: bodyRect.maxX + 6 * scale, y: headRect.minY - 2 * scale))
                },
                with: .color(QueueColors.sage),
                style: StrokeStyle(lineWidth: 3.4 * scale, lineCap: .round)
            )
            drawHand(context: &context, at: CGPoint(x: bodyRect.minX - 8 * scale, y: headRect.minY - 2 * scale), scale: scale)
            drawHand(context: &context, at: CGPoint(x: bodyRect.maxX + 4 * scale, y: headRect.minY - 2 * scale), scale: scale)

        case .levelUp:
            let starCenter = CGPoint(
                x: center.x,
                y: headRect.minY - 12 * scale + CGFloat(sin(time * 3.5)) * 1.5 * scale
            )
            drawStar(context: &context, at: starCenter, scale: scale, time: time)
            context.stroke(
                Path { path in
                    path.move(to: CGPoint(x: bodyRect.minX + 6 * scale, y: bodyRect.midY))
                    path.addLine(to: CGPoint(x: starCenter.x - 4 * scale, y: starCenter.y + 4 * scale))
                },
                with: .color(QueueColors.sage),
                style: StrokeStyle(lineWidth: 3 * scale, lineCap: .round)
            )
            context.stroke(
                Path { path in
                    path.move(to: CGPoint(x: bodyRect.maxX - 6 * scale, y: bodyRect.midY))
                    path.addLine(to: CGPoint(x: starCenter.x + 4 * scale, y: starCenter.y + 4 * scale))
                },
                with: .color(QueueColors.sage),
                style: StrokeStyle(lineWidth: 3 * scale, lineCap: .round)
            )
        }
    }

    private func drawHand(context: inout GraphicsContext, at point: CGPoint, scale: CGFloat) {
        context.fill(
            Path(ellipseIn: CGRect(x: point.x, y: point.y, width: 5.5 * scale, height: 4.5 * scale)),
            with: .color(QueueColors.sage.opacity(0.98))
        )
    }

    private func drawHourglass(context: inout GraphicsContext, at point: CGPoint, scale: CGFloat, empty: Bool) {
        let frame = CGRect(x: point.x - 4 * scale, y: point.y - 7 * scale, width: 8 * scale, height: 12 * scale)
        context.stroke(
            Path(roundedRect: frame, cornerRadius: 1 * scale),
            with: .color(Color(red: 0.55, green: 0.42, blue: 0.28).opacity(0.9)),
            style: StrokeStyle(lineWidth: 1.1 * scale)
        )
        if !empty {
            context.fill(
                Path(ellipseIn: CGRect(x: frame.midX - 2 * scale, y: frame.maxY - 4 * scale, width: 4 * scale, height: 2.5 * scale)),
                with: .color(QueueColors.reward.opacity(0.7))
            )
        }
    }

    private func drawStar(context: inout GraphicsContext, at point: CGPoint, scale: CGFloat, time: TimeInterval) {
        let glow = 0.55 + 0.25 * abs(sin(time * 4))
        context.fill(
            Path(ellipseIn: CGRect(x: point.x - 9 * scale, y: point.y - 9 * scale, width: 18 * scale, height: 18 * scale)),
            with: .color(QueueColors.reward.opacity(0.25 * glow))
        )
        context.fill(
            Path(ellipseIn: CGRect(x: point.x - 6 * scale, y: point.y - 6 * scale, width: 12 * scale, height: 12 * scale)),
            with: .color(QueueColors.reward.opacity(0.95))
        )
        context.fill(
            Path(ellipseIn: CGRect(x: point.x - 2.5 * scale, y: point.y - 2.5 * scale, width: 5 * scale, height: 5 * scale)),
            with: .color(QueueColors.ivory.opacity(0.9))
        )
    }

    private func drawSparkles(
        context: inout GraphicsContext,
        center: CGPoint,
        scale: CGFloat,
        time: TimeInterval,
        richer: Bool
    ) {
        let count = richer ? 10 : 6
        for i in 0..<count {
            let phase = time * (2.8 + Double(i) * 0.35) + Double(i)
            let orbit = 18 + Double(i % 3) * 6
            let x = center.x + CGFloat(cos(phase) * orbit) * scale
            let y = center.y - 18 * scale + CGFloat(sin(phase * 1.3) * 10) * scale
                - CGFloat((phase * 4).truncatingRemainder(dividingBy: 8)) * scale
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
            // Desk
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color(red: 0.42, green: 0.32, blue: 0.24).opacity(0.9))
                .frame(width: 64, height: 8)
                .offset(y: 22)

            // Body + head
            Circle()
                .fill(QueueColors.sage.opacity(0.95))
                .frame(width: 40, height: 40)
                .offset(y: -8)
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(QueueColors.sage)
                .frame(width: 48, height: 34)
                .offset(y: 10)

            // Laptop in front
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(QueueColors.charcoal.opacity(0.9))
                .frame(width: 28, height: 14)
                .overlay(
                    RoundedRectangle(cornerRadius: 1)
                        .fill(QueueColors.reward.opacity(state == .working ? 0.55 : 0.2))
                        .padding(3)
                )
                .offset(y: 8)

            if state == .working {
                Capsule()
                    .fill(QueueColors.sage)
                    .frame(width: 8, height: 5)
                    .offset(x: -6, y: 14)
                Capsule()
                    .fill(QueueColors.sage)
                    .frame(width: 8, height: 5)
                    .offset(x: 6, y: 14)
            }

            if state == .celebrating || state == .levelUp || state == .completed {
                Circle()
                    .fill(QueueColors.reward)
                    .frame(width: 6, height: 6)
                    .offset(x: 28, y: -20)
            }
            if state == .levelUp {
                Circle()
                    .fill(QueueColors.reward)
                    .frame(width: 12, height: 12)
                    .offset(y: -34)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
