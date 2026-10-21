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
    private static let typingWarpKey = "companion.typing.keyframes"
    private static let typingWarpFrames: [SKWarpGeometryGrid] = makeTypingWarpFrames()

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
        // Animate local geometry around the character's existing paws, not
        // a detached overlay or the desk. Do not restart on timer updates.
        let shouldType = isWorking && clip.playback == .loop
        if shouldType {
            if sprite.action(forKey: Self.typingWarpKey) == nil {
                let keyframes = Self.typingWarpFrames.map {
                    SKAction.warp(to: $0, duration: 0.055)
                }
                sprite.run(.repeatForever(.sequence(keyframes)),
                           withKey: Self.typingWarpKey)
            }
        } else {
            sprite.removeAction(forKey: Self.typingWarpKey)
            sprite.warpGeometry = nil
        }

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
        // Coordinates are in the same normalized 768-point design space as the art.
        // Mug rim is approximately (550, 457) in the 768-point source art.
        // SKScene uses a centered, Y-up coordinate system.
        steam.position = CGPoint(x: side * (550 - 384) / 768,
                                 y: side * (384 - 457) / 768)
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

    /// Twenty real deformation poses of the original illustrated hands.
    /// All vertices outside two small regions are mathematically unchanged,
    /// keeping the laptop, desk, mug, plant and lamp locked in place.
    /// Source image is 768x768; SpriteKit grid coordinates have Y pointing up.
    private static func makeTypingWarpFrames() -> [SKWarpGeometryGrid] {
        let columns = 32
        let rows = 32
        var original: [vector_float2] = []
        for row in 0...rows {
            for column in 0...columns {
                original.append(vector_float2(Float(column) / Float(columns),
                                              Float(row) / Float(rows)))
            }
        }
        return (0..<20).map { index in
            let phase = Float(index) * 2 * Float.pi / 20
            let moved = original.map { point -> vector_float2 in
                var displacement = vector_float2.zero
                // The visible hands sit at image positions roughly (390,460)
                // and (445,470). Convert image Y to SpriteKit bottom-up Y.
                let hands: [(Float, Float, Float)] = [
                    (0.505, 0.389, 0),
                    (0.574, 0.382, Float.pi)
                ]
                for (cx, cy, offset) in hands {
                    let dx = (point.x - cx) / 0.061
                    let dy = (point.y - cy) / 0.047
                    let radiusSquared = dx * dx + dy * dy
                    // Compact support: exactly zero outside each paw.
                    if radiusSquared < 1 {
                        let influence = pow(1 - radiusSquared, 2)
                        let press = (1 - cos(phase * 2 + offset)) / 2
                        displacement.x += influence * sin(phase + offset) * 0.004
                        displacement.y -= influence * press * 0.010
                    }
                }
                return point + displacement
            }
            return SKWarpGeometryGrid(columns: columns, rows: rows,
                                      sourcePositions: original,
                                      destinationPositions: moved)
        }
    }

    private static let animationKey = "companion.atlas"
}

