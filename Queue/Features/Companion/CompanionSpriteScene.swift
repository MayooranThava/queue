import SpriteKit

/// Single reusable SpriteKit scene for companion atlas playback.
/// The scene is created once by `CompanionSpriteView` and never rebuilt on timer ticks.
final class CompanionSpriteScene: SKScene {
    private let sprite = SKSpriteNode()
    private var appliedClip: CompanionAnimationClip?
    private var appliedGeneration: UInt = 0
    private var suspended = false
    // A subtle secondary motion layer, independent of the authored typing frames.
    private let steam = SKNode()
    private let typingMotionKey = "companion.typingMotion"
    private let typingTiltKey = "companion.typingTilt"
    private let typingPaws = SKSpriteNode()
    private let pawsActionKey = "companion.paws.frames"

    override init(size: CGSize) {
        super.init(size: size)
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
        scaleMode = .aspectFit
        backgroundColor = .clear
        isUserInteractionEnabled = false

        sprite.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        sprite.zPosition = 0
        // Avoid a blank node before the first texture arrives.
        sprite.color = .clear
        sprite.colorBlendFactor = 0
        addChild(sprite)
        typingPaws.zPosition = 2
        typingPaws.isHidden = true
        addChild(typingPaws)
        steam.zPosition = 1
        addChild(steam)
        configureSteam()
        layoutSprite()
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMove(to view: SKView) {
        view.allowsTransparency = true
        view.isOpaque = false
        view.backgroundColor = .clear
        backgroundColor = .clear
        isPaused = suspended
        layoutSprite()
        // Re-assert the current clip once the view is attached (textures may load late).
        if let clip = appliedClip {
            let generation = appliedGeneration
            appliedClip = nil
            apply(clip: clip, generation: generation)
        }
    }

    override func didChangeSize(_ oldSize: CGSize) {
        layoutSprite()
    }

    /// Suspend looping / one-shot actions when the app is backgrounded.
    func setPlaybackSuspended(_ suspended: Bool) {
        guard self.suspended != suspended else { return }
        self.suspended = suspended
        isPaused = suspended
    }

    /// Apply a clip. `generation` bumps when the SwiftUI state changes so one-shots can restart.
    func apply(clip: CompanionAnimationClip, generation: UInt) {
        let textures = CompanionTextureStore.shared.textures(for: clip.atlas)
        guard !textures.isEmpty else { return }

        let sameClip = appliedClip == clip && appliedGeneration == generation
        appliedClip = clip
        appliedGeneration = generation

        let isWorking = clip.atlas == .working || clip.atlas == .deepFocus
        steam.isHidden = clip.playback == .staticFrame || !isWorking
        // Never shake the whole illustration. Only the transparent paw layer
        // animates; the background, laptop, desk and lamp stay anchored.
        sprite.removeAction(forKey: typingMotionKey)
        sprite.removeAction(forKey: typingTiltKey)
        sprite.position = .zero
        sprite.yScale = 1
        sprite.zRotation = 0
        // Production safety: disable the prototype paw overlay. Its generated
        // ovals are not registered to the illustrated character's hands and
        // appear as floating dots on the desk. Keep authored atlas playback.
        typingPaws.isHidden = true
        typingPaws.removeAction(forKey: pawsActionKey)

        switch clip.playback {
        case .staticFrame:
            sprite.removeAction(forKey: Self.animationKey)
            if let pose = clip.staticTexture(from: textures) {
                sprite.texture = pose
            }

        case .loop:
            if sameClip, sprite.action(forKey: Self.animationKey) != nil {
                return
            }
            sprite.texture = textures[0]
            let animate = SKAction.animate(
                with: textures,
                timePerFrame: clip.timePerFrame,
                resize: false,
                restore: false
            )
            sprite.run(SKAction.repeatForever(animate), withKey: Self.animationKey)

        case .playOnceHoldLast:
            if sameClip, sprite.action(forKey: Self.animationKey) != nil {
                return
            }
            let last = textures[textures.count - 1]
            sprite.texture = textures[0]
            let animate = SKAction.animate(
                with: textures,
                timePerFrame: clip.timePerFrame,
                resize: false,
                restore: false
            )
            let hold = SKAction.run { [weak self] in
                self?.sprite.texture = last
            }
            sprite.run(SKAction.sequence([animate, hold]), withKey: Self.animationKey)
        }
    }

    private func layoutSprite() {
        let side = min(size.width, size.height)
        guard side > 0 else { return }
        // Identical size / scale / anchor for every frame — prevents desk / laptop drift.
        sprite.size = CGSize(width: side, height: side)
        // Preserve animated transforms across layout and timer updates.
        sprite.isHidden = false
        sprite.alpha = 1
        typingPaws.size = CGSize(width: side * 136 / 768, height: side * 76 / 768)
        typingPaws.position = CGPoint(x: side * 0.105, y: -side * 0.20)
        // Coordinates are in the same normalized 768-point design space as the art.
        steam.position = CGPoint(x: side * 0.23, y: side * 0.065)
        steam.setScale(side / 768)
    }

    private func configureSteam() {
        // Low-contrast wisps drift upward and fade, without changing the atlas frame bounds.
        for index in 0..<3 {
            let wisp = SKShapeNode(ellipseOf: CGSize(width: 7, height: 13))
            wisp.fillColor = SKColor(white: 0.86, alpha: 0.32)
            wisp.strokeColor = .clear
            wisp.alpha = 0
            wisp.position = CGPoint(x: CGFloat(index * 6 - 6), y: 0)
            steam.addChild(wisp)
            let rise = SKAction.group([
                SKAction.moveBy(x: CGFloat(index - 1) * 9, y: 48, duration: 2.1),
                SKAction.sequence([
                    SKAction.fadeAlpha(to: 0.42, duration: 0.6),
                    SKAction.fadeOut(withDuration: 1.5)
                ])
            ])
            let reset = SKAction.run { [weak wisp] in
                wisp?.position = CGPoint(x: CGFloat(index * 6 - 6), y: 0)
                wisp?.alpha = 0
            }
            let delay = SKAction.wait(forDuration: Double(index) * 0.7)
            let cycle = SKAction.sequence([rise, reset])
            wisp.run(SKAction.sequence([delay, SKAction.repeatForever(cycle)]))
        }
    }

    private static let typingAtlasFrames: [SKTexture] = {
        let atlas = SKTextureAtlas(named: "Typing")
        let frames = CompanionTextureStore.orderedTextures(from: atlas)
        return frames.count == 20 ? frames : CompanionTypingFrames.textures
    }()

    private static let animationKey = "companion.atlas"
}


/// A transparent 20-frame overlay for the companion's two typing paws.
/// The desk, laptop and character artwork remain completely stationary.
/// Textures are generated once and reused instead of allocating every timer tick.
enum CompanionTypingFrames {
    static let textures: [SKTexture] = (0..<20).map { frame in
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: CGSize(width: 136, height: 76), format: format).image { renderer in
            let context = renderer.cgContext
            let phase = CGFloat(frame) * (.pi * 2 / 20)
            for paw in 0..<2 {
                let alternate = paw == 0 ? CGFloat(0) : .pi
                // Alternating key presses with a small natural follow-through.
                let press = (1 - cos(phase * 2 + alternate)) * 0.5
                let horizontal = sin(phase + alternate) * 2.8
                let centerX = CGFloat(paw == 0 ? 47 : 91) + horizontal
                let centerY = CGFloat(paw == 0 ? 36 : 39) + press * 6
                context.saveGState()
                context.setShadow(offset: CGSize(width: 1, height: 3), blur: 4,
                                  color: UIColor(red: 0.30, green: 0.18, blue: 0.13, alpha: 0.25).cgColor)
                let outline = CGRect(x: centerX - 19, y: centerY - 13, width: 38, height: 26)
                let path = UIBezierPath(roundedRect: outline, cornerRadius: 13)
                UIColor(red: 0.97, green: 0.88, blue: 0.73, alpha: 1).setFill()
                path.fill()
                context.restoreGState()
                // Soft lit upper surface, with subtle individual toe impressions.
                let highlight = UIBezierPath(ovalIn: CGRect(x: centerX - 16, y: centerY - 12,
                                                             width: 30, height: 17))
                UIColor(red: 1, green: 0.97, blue: 0.87, alpha: 0.93).setFill()
                highlight.fill()
                UIColor(red: 0.85, green: 0.72, blue: 0.62, alpha: 0.18).setStroke()
                for finger in 0..<3 {
                    let line = UIBezierPath()
                    let x = centerX - 7 + CGFloat(finger) * 7
                    line.move(to: CGPoint(x: x, y: centerY + 5))
                    line.addLine(to: CGPoint(x: x + 1, y: centerY + 9))
                    line.lineWidth = 1
                    line.stroke()
                }
            }
        }
        let texture = SKTexture(image: image)
        texture.filteringMode = .linear
        return texture
    }
}
