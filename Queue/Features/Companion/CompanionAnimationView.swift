import SwiftUI

/// Production companion entry point. Rive-ready abstraction; native Canvas fallback.
/// Design coordinate system: 512×512, scaled to the view.
struct CompanionAnimationView: View, CompanionAnimationRendering {
    let state: CompanionAnimationState
    let reduceMotion: Bool
    var compact: Bool = false

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.scenePhase) private var scenePhase

    private var shouldAnimate: Bool {
        !reduceMotion && !systemReduceMotion && scenePhase == .active
    }

    var body: some View {
        Group {
            if shouldAnimate {
                CompanionSceneView(state: state, compact: compact)
            } else {
                CompanionStaticPose(state: state)
            }
        }
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        switch state {
        case .idle: return "Companion resting"
        case .preparing: return "Companion getting ready"
        case .working: return "Companion focusing with you"
        case .deepFocus: return "Companion in deep focus"
        case .paused: return "Companion paused"
        case .completed, .celebrating: return "Companion celebrating"
        case .levelUp: return "Companion celebrating a level up"
        case .timerExpired: return "Companion waiting thoughtfully"
        }
    }
}

// MARK: - Scene

struct CompanionSceneView: View {
    let state: CompanionAnimationState
    var compact: Bool = false

    /// One-shot sequences track local start so celebrate / expire play once per appearance.
    @State private var sequenceStartedAt = Date()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: false)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let sequenceTime = timeline.date.timeIntervalSince(sequenceStartedAt)
            Canvas { context, size in
                CompanionSceneRenderer.draw(
                    context: &context,
                    size: size,
                    state: state,
                    time: time,
                    sequenceTime: sequenceTime,
                    compact: compact
                )
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .onChange(of: state) { _, _ in
            sequenceStartedAt = Date()
        }
    }
}

// MARK: - Renderer (fixed 512 design space)

enum CompanionSceneRenderer {
    static let design: CGFloat = 512

    // Cream companion + cozy desk palette from concept sheet
    static let cream = Color(red: 0.96, green: 0.93, blue: 0.86)
    static let creamShadow = Color(red: 0.90, green: 0.86, blue: 0.78)
    static let wood = Color(red: 0.45, green: 0.32, blue: 0.22)
    static let woodLight = Color(red: 0.58, green: 0.42, blue: 0.28)
    static let lampGlow = Color(red: 1.0, green: 0.85, blue: 0.45)
    static let headphone = Color(red: 0.42, green: 0.52, blue: 0.38)
    static let plant = Color(red: 0.45, green: 0.62, blue: 0.42)
    static let bookYellow = Color(red: 0.85, green: 0.72, blue: 0.35)
    static let bookGreen = Color(red: 0.40, green: 0.55, blue: 0.42)

    static func draw(
        context: inout GraphicsContext,
        size: CGSize,
        state: CompanionAnimationState,
        time: TimeInterval,
        sequenceTime: TimeInterval,
        compact: Bool
    ) {
        let scale = min(size.width, size.height) / design
        let origin = CGPoint(
            x: (size.width - design * scale) / 2,
            y: (size.height - design * scale) / 2
        )

        func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: origin.x + x * scale, y: origin.y + y * scale)
        }
        func S(_ v: CGFloat) -> CGFloat { v * scale }

        // Fixed camera — soft floor shadow
        context.fill(
            Path(ellipseIn: CGRect(x: P(160, 430).x, y: P(160, 430).y, width: S(192), height: S(28))),
            with: .color(Color.black.opacity(0.22))
        )

        drawDesk(context: &context, P: P, S: S)
        drawBooks(context: &context, P: P, S: S)
        drawPlant(context: &context, P: P, S: S)
        drawLamp(context: &context, P: P, S: S, time: time, lit: state == .working || state == .deepFocus || state == .preparing)

        // Motion parameters by state
        let motion = motionParams(state: state, time: time, sequenceTime: sequenceTime)

        drawCharacter(
            context: &context,
            P: P,
            S: S,
            state: state,
            motion: motion,
            time: time,
            sequenceTime: sequenceTime
        )

        drawLaptop(context: &context, P: P, S: S, glow: motion.screenGlow)

        // Arms / hands in front of laptop for typing states
        drawArms(
            context: &context,
            P: P,
            S: S,
            state: state,
            motion: motion
        )

        drawEffects(
            context: &context,
            P: P,
            S: S,
            state: state,
            motion: motion,
            time: time,
            sequenceTime: sequenceTime
        )
    }

    private struct Motion {
        var breath: CGFloat
        var headLean: CGFloat
        var leftHandY: CGFloat
        var rightHandY: CGFloat
        var eyeOpen: CGFloat
        var smile: CGFloat
        var armsUp: CGFloat
        var bounce: CGFloat
        var screenGlow: Double
        var holdStar: Bool
        var showHeadphones: Bool
        var showHourglass: Bool
        var thoughtPhase: CGFloat
    }

    private static func motionParams(
        state: CompanionAnimationState,
        time: TimeInterval,
        sequenceTime: TimeInterval
    ) -> Motion {
        // Independent blink (~every 2.8–4.2s, brief close)
        let blinkCycle = time * 0.37
        let blink = (sin(blinkCycle) > 0.94) ? 0.2 : 1.0

        switch state {
        case .working:
            // 2.6s primary typing loop — seamless sin waves
            let loop = time * (.pi * 2 / 2.6)
            let type = sin(loop)
            let type2 = sin(loop + 1.3)
            return Motion(
                breath: CGFloat(sin(time * 1.4)) * 2.2,
                headLean: CGFloat(sin(time * 0.8)) * 3.5,
                leftHandY: CGFloat(type) * 5,
                rightHandY: CGFloat(type2) * 5,
                eyeOpen: CGFloat(blink),
                smile: 0.15,
                armsUp: 0,
                bounce: 0,
                screenGlow: 0.5 + 0.2 * (0.5 + 0.5 * sin(time * 4.5)),
                holdStar: false,
                showHeadphones: false,
                showHourglass: false,
                thoughtPhase: 0
            )

        case .deepFocus:
            let loop = time * (.pi * 2 / 3.5)
            let closed = (sin(time * 0.55) > 0.15) ? 0.15 : blink
            return Motion(
                breath: CGFloat(sin(time * 1.05)) * 1.6,
                headLean: CGFloat(sin(time * 0.45)) * 2.0,
                leftHandY: CGFloat(sin(loop)) * 1.5,
                rightHandY: CGFloat(sin(loop + 1.1)) * 1.5,
                eyeOpen: CGFloat(closed),
                smile: 0.1,
                armsUp: 0,
                bounce: 0,
                screenGlow: 0.35,
                holdStar: false,
                showHeadphones: true,
                showHourglass: false,
                thoughtPhase: 0
            )

        case .paused, .idle:
            return Motion(
                breath: CGFloat(sin(time * 0.9)) * 1.4,
                headLean: state == .paused ? -2 : CGFloat(sin(time * 0.3)) * 1.5,
                leftHandY: 0,
                rightHandY: 0,
                eyeOpen: state == .paused ? 0.25 : CGFloat(blink),
                smile: 0,
                armsUp: 0,
                bounce: 0,
                screenGlow: 0.12,
                holdStar: false,
                showHeadphones: false,
                showHourglass: false,
                thoughtPhase: state == .idle ? CGFloat(sin(time * 2)) : 0
            )

        case .preparing:
            return Motion(
                breath: CGFloat(sin(time * 1.2)) * 2.0,
                headLean: CGFloat(sin(time * 1.5)) * 2,
                leftHandY: 0,
                rightHandY: 0,
                eyeOpen: CGFloat(blink),
                smile: 0.2,
                armsUp: 0,
                bounce: 0,
                screenGlow: 0.22 + 0.06 * sin(time * 2.5),
                holdStar: false,
                showHeadphones: false,
                showHourglass: false,
                thoughtPhase: 0
            )

        case .completed, .celebrating, .levelUp:
            // One-shot ~1.7s timeline from concept
            let t = min(1.7, max(0, sequenceTime))
            let arms: CGFloat = {
                if t < 0.2 { return 0 }
                if t < 0.5 { return CGFloat((t - 0.2) / 0.3) }
                if t < 1.3 { return 1 }
                return 1 - CGFloat((t - 1.3) / 0.4) * 0.25
            }()
            let bounce: CGFloat = {
                if t < 0.9 { return 0 }
                if t < 1.3 { return abs(sin((t - 0.9) / 0.4 * .pi)) * 10 }
                return 0
            }()
            let smile: CGFloat = t < 0.2 ? 0.2 : 1
            return Motion(
                breath: CGFloat(sin(time * 2)) * 1.5,
                headLean: 0,
                leftHandY: 0,
                rightHandY: 0,
                eyeOpen: 1,
                smile: smile,
                armsUp: arms,
                bounce: bounce,
                screenGlow: 0.25,
                holdStar: state == .levelUp && t > 0.9,
                showHeadphones: false,
                showHourglass: false,
                thoughtPhase: 0
            )

        case .timerExpired:
            let t = min(1.5, max(0, sequenceTime))
            let thought: CGFloat = (t > 0.35 && t < 1.1) ? 1 : (t >= 1.1 ? 0.5 : 0)
            return Motion(
                breath: CGFloat(sin(time * 1.0)) * 1.2,
                headLean: t < 0.4 ? 4 : (t < 0.9 ? -3 : 0),
                leftHandY: 0,
                rightHandY: 0,
                eyeOpen: t < 0.5 ? 1.1 : 0.85,
                smile: 0,
                armsUp: 0,
                bounce: 0,
                screenGlow: 0.1,
                holdStar: false,
                showHeadphones: false,
                showHourglass: true,
                thoughtPhase: thought
            )
        }
    }

    // MARK: Props (fixed)

    private static func drawDesk(context: inout GraphicsContext, P: (CGFloat, CGFloat) -> CGPoint, S: (CGFloat) -> CGFloat) {
        let desk = CGRect(x: P(64, 360).x, y: P(64, 360).y, width: S(384), height: S(48))
        context.fill(Path(roundedRect: desk, cornerRadius: S(10)), with: .color(wood))
        context.fill(
            Path(roundedRect: CGRect(x: desk.minX + S(8), y: desk.minY + S(6), width: desk.width - S(16), height: S(10)), cornerRadius: S(4)),
            with: .color(woodLight.opacity(0.55))
        )
    }

    private static func drawBooks(context: inout GraphicsContext, P: (CGFloat, CGFloat) -> CGPoint, S: (CGFloat) -> CGFloat) {
        context.fill(Path(roundedRect: CGRect(x: P(390, 332).x, y: P(390, 332).y, width: S(52), height: S(14)), cornerRadius: S(2)), with: .color(bookYellow))
        context.fill(Path(roundedRect: CGRect(x: P(396, 318).x, y: P(396, 318).y, width: S(46), height: S(14)), cornerRadius: S(2)), with: .color(bookGreen))
    }

    private static func drawPlant(context: inout GraphicsContext, P: (CGFloat, CGFloat) -> CGPoint, S: (CGFloat) -> CGFloat) {
        context.fill(Path(roundedRect: CGRect(x: P(86, 330).x, y: P(86, 330).y, width: S(28), height: S(22)), cornerRadius: S(4)), with: .color(Color(red: 0.55, green: 0.5, blue: 0.45)))
        context.fill(Path(ellipseIn: CGRect(x: P(78, 292).x, y: P(78, 292).y, width: S(22), height: S(34))), with: .color(plant))
        context.fill(Path(ellipseIn: CGRect(x: P(96, 286).x, y: P(96, 286).y, width: S(24), height: S(36))), with: .color(plant.opacity(0.85)))
    }

    private static func drawLamp(
        context: inout GraphicsContext,
        P: (CGFloat, CGFloat) -> CGPoint,
        S: (CGFloat) -> CGFloat,
        time: TimeInterval,
        lit: Bool
    ) {
        let base = P(360, 350)
        context.fill(Path(ellipseIn: CGRect(x: base.x - S(14), y: base.y - S(6), width: S(28), height: S(12))), with: .color(QueueColors.charcoal))
        var arm = Path()
        arm.move(to: CGPoint(x: base.x, y: base.y - S(4)))
        arm.addLine(to: CGPoint(x: base.x + S(8), y: base.y - S(70)))
        context.stroke(arm, with: .color(QueueColors.charcoal.opacity(0.9)), style: StrokeStyle(lineWidth: S(5), lineCap: .round))
        context.fill(
            Path(ellipseIn: CGRect(x: base.x - S(6), y: base.y - S(92), width: S(40), height: S(24))),
            with: .color(Color(red: 0.92, green: 0.78, blue: 0.4))
        )
        if lit {
            let pulse = 0.14 + 0.04 * sin(time * 2.8)
            context.fill(
                Path(ellipseIn: CGRect(x: base.x - S(50), y: base.y - S(70), width: S(120), height: S(90))),
                with: .color(lampGlow.opacity(pulse))
            )
        }
    }

    private static func drawLaptop(
        context: inout GraphicsContext,
        P: (CGFloat, CGFloat) -> CGPoint,
        S: (CGFloat) -> CGFloat,
        glow: Double
    ) {
        let origin = P(196, 300)
        context.fill(
            Path(roundedRect: CGRect(x: origin.x, y: origin.y + S(42), width: S(120), height: S(18)), cornerRadius: S(4)),
            with: .color(QueueColors.charcoal.opacity(0.95))
        )
        context.fill(
            Path(roundedRect: CGRect(x: origin.x + S(8), y: origin.y, width: S(104), height: S(56)), cornerRadius: S(6)),
            with: .color(QueueColors.charcoal)
        )
        context.fill(
            Path(roundedRect: CGRect(x: origin.x + S(16), y: origin.y + S(8), width: S(88), height: S(38)), cornerRadius: S(3)),
            with: .color(QueueColors.reward.opacity(glow))
        )
        // Leaf logo
        context.fill(
            Path(ellipseIn: CGRect(x: origin.x + S(52), y: origin.y + S(22), width: S(16), height: S(12))),
            with: .color(cream.opacity(0.9))
        )
    }

    private static func drawCharacter(
        context: inout GraphicsContext,
        P: (CGFloat, CGFloat) -> CGPoint,
        S: (CGFloat) -> CGFloat,
        state: CompanionAnimationState,
        motion: Motion,
        time: TimeInterval,
        sequenceTime: TimeInterval
    ) {
        let bodyCenter = P(256 + motion.headLean * 0.15, 268 - motion.breath - motion.bounce)
        let bodyW = S(150)
        let bodyH = S(130)
        let bodyRect = CGRect(x: bodyCenter.x - bodyW / 2, y: bodyCenter.y - bodyH / 2, width: bodyW, height: bodyH)
        context.fill(Path(ellipseIn: bodyRect), with: .color(cream))
        // Soft right-side warm light
        context.fill(
            Path(ellipseIn: CGRect(x: bodyRect.midX, y: bodyRect.minY + S(10), width: S(50), height: S(90))),
            with: .color(lampGlow.opacity(0.08))
        )

        let headCenter = CGPoint(x: bodyCenter.x + S(motion.headLean), y: bodyRect.minY - S(28))
        let headW = S(112)
        let headH = S(100)
        let headRect = CGRect(x: headCenter.x - headW / 2, y: headCenter.y - headH / 2, width: headW, height: headH)
        context.fill(Path(ellipseIn: headRect), with: .color(cream))

        if motion.showHeadphones {
            context.stroke(
                Path { path in
                    path.addArc(center: headCenter, radius: S(58), startAngle: .degrees(200), endAngle: .degrees(340), clockwise: false)
                },
                with: .color(headphone),
                style: StrokeStyle(lineWidth: S(10), lineCap: .round)
            )
            context.fill(Path(ellipseIn: CGRect(x: headRect.minX - S(10), y: headCenter.y - S(18), width: S(22), height: S(36))), with: .color(headphone))
            context.fill(Path(ellipseIn: CGRect(x: headRect.maxX - S(12), y: headCenter.y - S(18), width: S(22), height: S(36))), with: .color(headphone))
        }

        // Eyes — consistent positions
        let eyeY = headCenter.y - S(4)
        let eyeH = max(S(2), S(10) * motion.eyeOpen)
        context.fill(Path(ellipseIn: CGRect(x: headCenter.x - S(22), y: eyeY - eyeH / 2, width: S(12), height: eyeH)), with: .color(QueueColors.ink))
        context.fill(Path(ellipseIn: CGRect(x: headCenter.x + S(10), y: eyeY - eyeH / 2, width: S(12), height: eyeH)), with: .color(QueueColors.ink))

        // Mouth
        if motion.smile > 0.5 {
            var smile = Path()
            smile.addArc(center: CGPoint(x: headCenter.x, y: headCenter.y + S(14)), radius: S(16), startAngle: .degrees(20), endAngle: .degrees(160), clockwise: false)
            context.stroke(smile, with: .color(QueueColors.ink.opacity(0.65)), style: StrokeStyle(lineWidth: S(3.5), lineCap: .round))
        } else if motion.smile > 0 {
            context.stroke(
                Path { p in
                    p.move(to: CGPoint(x: headCenter.x - S(8), y: headCenter.y + S(18)))
                    p.addLine(to: CGPoint(x: headCenter.x + S(8), y: headCenter.y + S(18)))
                },
                with: .color(QueueColors.ink.opacity(0.45)),
                style: StrokeStyle(lineWidth: S(3), lineCap: .round)
            )
        }

        if motion.holdStar {
            let star = CGPoint(x: headCenter.x, y: headRect.minY - S(36))
            context.fill(Path(ellipseIn: CGRect(x: star.x - S(36), y: star.y - S(36), width: S(72), height: S(72))), with: .color(QueueColors.reward.opacity(0.25)))
            context.fill(Path(ellipseIn: CGRect(x: star.x - S(22), y: star.y - S(22), width: S(44), height: S(44))), with: .color(QueueColors.reward))
            context.fill(Path(ellipseIn: CGRect(x: star.x - S(10), y: star.y - S(10), width: S(20), height: S(20))), with: .color(cream))
        }

        if motion.showHourglass {
            let hx = P(400, 280)
            context.stroke(
                Path(roundedRect: CGRect(x: hx.x, y: hx.y, width: S(28), height: S(44)), cornerRadius: S(4)),
                with: .color(woodLight),
                style: StrokeStyle(lineWidth: S(3))
            )
            context.fill(Path(ellipseIn: CGRect(x: hx.x + S(6), y: hx.y + S(28), width: S(16), height: S(10))), with: .color(QueueColors.reward.opacity(0.7)))
        }
    }

    private static func drawArms(
        context: inout GraphicsContext,
        P: (CGFloat, CGFloat) -> CGPoint,
        S: (CGFloat) -> CGFloat,
        state: CompanionAnimationState,
        motion: Motion
    ) {
        let shoulderY = P(0, 290).y
        let leftShoulder = P(190, 290)
        let rightShoulder = P(322, 290)

        if motion.armsUp > 0 {
            let lift = motion.armsUp
            let leftHand = CGPoint(x: leftShoulder.x - S(40) * lift, y: shoulderY - S(90) * lift)
            let rightHand = CGPoint(x: rightShoulder.x + S(40) * lift, y: shoulderY - S(90) * lift)
            strokeArm(context: &context, from: leftShoulder, to: leftHand, S: S)
            strokeArm(context: &context, from: rightShoulder, to: rightHand, S: S)
            fillHand(context: &context, at: leftHand, S: S)
            fillHand(context: &context, at: rightHand, S: S)
            return
        }

        switch state {
        case .working, .deepFocus:
            let leftHand = CGPoint(x: P(220, 0).x, y: P(0, 348).y + S(motion.leftHandY))
            let rightHand = CGPoint(x: P(292, 0).x, y: P(0, 348).y + S(motion.rightHandY))
            strokeArm(context: &context, from: leftShoulder, to: leftHand, S: S)
            strokeArm(context: &context, from: rightShoulder, to: rightHand, S: S)
            fillHand(context: &context, at: leftHand, S: S)
            fillHand(context: &context, at: rightHand, S: S)
        case .preparing:
            let mug = P(240, 330)
            context.fill(Path(roundedRect: CGRect(x: mug.x, y: mug.y, width: S(36), height: S(32)), cornerRadius: S(6)), with: .color(bookGreen))
            fillHand(context: &context, at: CGPoint(x: mug.x - S(4), y: mug.y + S(10)), S: S)
            fillHand(context: &context, at: CGPoint(x: mug.x + S(28), y: mug.y + S(10)), S: S)
        default:
            break
        }
    }

    private static func strokeArm(context: inout GraphicsContext, from: CGPoint, to: CGPoint, S: (CGFloat) -> CGFloat) {
        var path = Path()
        path.move(to: from)
        path.addQuadCurve(to: to, control: CGPoint(x: (from.x + to.x) / 2, y: max(from.y, to.y) + S(8)))
        context.stroke(path, with: .color(cream), style: StrokeStyle(lineWidth: S(16), lineCap: .round))
    }

    private static func fillHand(context: inout GraphicsContext, at: CGPoint, S: (CGFloat) -> CGFloat) {
        context.fill(Path(ellipseIn: CGRect(x: at.x - S(12), y: at.y - S(9), width: S(24), height: S(18))), with: .color(cream))
    }

    private static func drawEffects(
        context: inout GraphicsContext,
        P: (CGFloat, CGFloat) -> CGPoint,
        S: (CGFloat) -> CGFloat,
        state: CompanionAnimationState,
        motion: Motion,
        time: TimeInterval,
        sequenceTime: TimeInterval
    ) {
        if state == .deepFocus {
            let alpha = 0.35 + 0.25 * abs(sin(time * 1.8))
            let note = P(340 + CGFloat(sin(time) * 6), 180 + CGFloat(cos(time * 1.3) * 8))
            context.fill(Path(ellipseIn: CGRect(x: note.x, y: note.y, width: S(12), height: S(12))), with: .color(QueueColors.reward.opacity(alpha)))
        }

        if state == .idle, motion.thoughtPhase != 0 {
            let bubble = P(340, 160)
            context.fill(
                Path(ellipseIn: CGRect(x: bubble.x, y: bubble.y, width: S(70), height: S(44))),
                with: .color(Color.white.opacity(0.12))
            )
            for i in 0..<3 {
                let pulse = 0.35 + 0.35 * abs(sin(time * 2.2 + Double(i)))
                context.fill(
                    Path(ellipseIn: CGRect(x: bubble.x + S(16 + CGFloat(i) * 14), y: bubble.y + S(16), width: S(8), height: S(8))),
                    with: .color(Color.white.opacity(pulse))
                )
            }
        }

        if state == .timerExpired, motion.thoughtPhase > 0 {
            let bubble = P(330, 150)
            context.fill(Path(ellipseIn: CGRect(x: bubble.x, y: bubble.y, width: S(64), height: S(48))), with: .color(Color.white.opacity(0.12)))
            if sequenceTime > 1.1 {
                // Lightbulb cue
                context.fill(Path(ellipseIn: CGRect(x: bubble.x + S(18), y: bubble.y + S(8), width: S(28), height: S(28))), with: .color(lampGlow.opacity(0.85)))
            } else {
                context.stroke(
                    Path { p in
                        p.move(to: CGPoint(x: bubble.x + S(16), y: bubble.y + S(24)))
                        p.addCurve(
                            to: CGPoint(x: bubble.x + S(48), y: bubble.y + S(24)),
                            control1: CGPoint(x: bubble.x + S(24), y: bubble.y + S(8)),
                            control2: CGPoint(x: bubble.x + S(40), y: bubble.y + S(40))
                        )
                    },
                    with: .color(Color.white.opacity(0.55)),
                    style: StrokeStyle(lineWidth: S(3), lineCap: .round)
                )
            }
        }

        if state == .celebrating || state == .completed || state == .levelUp {
            let t = sequenceTime
            guard t > 0.45, t < 1.7 else { return }
            let count = state == .levelUp ? 12 : 8
            for i in 0..<count {
                let phase = (t - 0.45) * 3.2 + Double(i) * 0.55
                let radius = 40 + Double(i % 4) * 18
                let x = 256 + cos(phase + Double(i)) * radius
                let y = 200 + sin(phase * 1.2) * (28 + Double(i % 3) * 10) - (t - 0.45) * 20
                let alpha = max(0, 0.75 - (t - 0.45) * 0.45)
                let size: CGFloat = (i % 2 == 0) ? 10 : 6
                context.fill(
                    Path(ellipseIn: CGRect(x: P(CGFloat(x), CGFloat(y)).x, y: P(CGFloat(x), CGFloat(y)).y, width: S(size), height: S(size))),
                    with: .color((i % 3 == 0 ? QueueColors.reward : cream).opacity(alpha))
                )
            }
        }
    }
}

struct CompanionStaticPose: View {
    let state: CompanionAnimationState

    var body: some View {
        ZStack {
            Capsule()
                .fill(Color(red: 0.45, green: 0.32, blue: 0.22))
                .frame(width: 120, height: 14)
                .offset(y: 48)
            Circle()
                .fill(Color(red: 0.96, green: 0.93, blue: 0.86))
                .frame(width: 54, height: 54)
                .offset(y: -18)
            Capsule()
                .fill(Color(red: 0.96, green: 0.93, blue: 0.86))
                .frame(width: 72, height: 56)
                .offset(y: 16)
            RoundedRectangle(cornerRadius: 4)
                .fill(QueueColors.charcoal)
                .frame(width: 48, height: 28)
                .overlay(
                    RoundedRectangle(cornerRadius: 2)
                        .fill(QueueColors.reward.opacity(state == .working || state == .deepFocus ? 0.55 : 0.2))
                        .padding(4)
                )
                .offset(y: 14)
            if state == .celebrating || state == .levelUp || state == .completed {
                Circle()
                    .fill(QueueColors.reward)
                    .frame(width: 14, height: 14)
                    .offset(y: -52)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#if DEBUG
#Preview("Working") {
    CompanionAnimationView(state: .working, reduceMotion: false)
        .frame(width: 240, height: 240)
        .background(QueueColors.charcoal)
}
#Preview("Deep Focus") {
    CompanionAnimationView(state: .deepFocus, reduceMotion: false)
        .frame(width: 240, height: 240)
        .background(QueueColors.charcoal)
}
#Preview("Completed") {
    CompanionAnimationView(state: .celebrating, reduceMotion: false)
        .frame(width: 240, height: 240)
        .background(QueueColors.charcoal)
}
#Preview("Timer Expired") {
    CompanionAnimationView(state: .timerExpired, reduceMotion: false)
        .frame(width: 240, height: 240)
        .background(QueueColors.charcoal)
}
#Preview("Idle") {
    CompanionAnimationView(state: .idle, reduceMotion: false)
        .frame(width: 240, height: 240)
        .background(QueueColors.charcoal)
}
#endif
