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
        isPaused = false
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

        layoutSprite()
        steam.isHidden = clip.playback == .staticFrame || (clip.atlas != .working && clip.atlas != .deepFocus)

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
        sprite.position = .zero
        sprite.xScale = 1
        sprite.yScale = 1
        sprite.isHidden = false
        sprite.alpha = 1
        // Coordinates are in the same normalized 768-point design space as the art.
        steam.position = CGPoint(x: side * 0.23, y: side * 0.065)
        steam.setScale(side / 768)
    }

    private func configureSteam() {
        // Low-contrast wisps drift upward and fade, without changing the atlas frame bounds.
        for index in 0..<3 {
            let wisp = SKShapeNode(ellipseOf: CGSize(width: 7, height: 13))
            wisp.fillColor = SKColor(white: 1, alpha: 0.32)
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
            wisp.run(SKAction.sequence([delay, SKAction.repeatForever(SKAction.sequence([rise, reset]))]))
        }
    }

    private static let animationKey = "companion.atlas"
}
