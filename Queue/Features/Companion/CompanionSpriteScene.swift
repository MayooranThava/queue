import SpriteKit

/// Single reusable SpriteKit scene for companion atlas playback.
/// The scene is created once by `CompanionSpriteView` and never rebuilt on timer ticks.
final class CompanionSpriteScene: SKScene {
    private let sprite = SKSpriteNode()
    private var appliedClip: CompanionAnimationClip?
    private var appliedGeneration: UInt = 0
    private var suspended = false

    override init(size: CGSize) {
        super.init(size: size)
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
        scaleMode = .aspectFit
        backgroundColor = .clear
        isUserInteractionEnabled = false

        sprite.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        sprite.zPosition = 0
        addChild(sprite)
        layoutSprite()
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMove(to view: SKView) {
        view.allowsTransparency = true
        backgroundColor = .clear
        layoutSprite()
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

        switch clip.playback {
        case .staticFrame:
            sprite.removeAction(forKey: Self.animationKey)
            if let pose = clip.staticTexture(from: textures) {
                // Set texture before clearing action path to avoid an empty frame.
                sprite.texture = pose
            }

        case .loop:
            if sameClip, sprite.action(forKey: Self.animationKey) != nil {
                return
            }
            // Seed the first frame before swapping the action — no flash / empty frame.
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
    }

    private static let animationKey = "companion.atlas"
}
