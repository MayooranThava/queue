import SpriteKit
import SwiftUI

/// SwiftUI host for the companion SpriteKit scene.
/// The `SKScene` lives in the coordinator and is not recreated on Focus timer ticks.
struct CompanionSpriteView: UIViewRepresentable {
    var state: CompanionAnimationState
    var shouldAnimate: Bool
    var isSceneActive: Bool
    /// Bumps when `state` changes so one-shot clips restart cleanly.
    var sequenceGeneration: UInt

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> SKView {
        CompanionTextureStore.shared.preloadIfNeeded()

        let view = SKView(frame: CGRect(x: 0, y: 0, width: 240, height: 240))
        view.allowsTransparency = true
        view.isOpaque = false
        view.backgroundColor = .clear
        view.ignoresSiblingOrder = true
        view.isAsynchronous = true
        view.preferredFramesPerSecond = 60
        #if DEBUG
        view.showsFPS = false
        view.showsNodeCount = false
        #endif

        let scene = CompanionSpriteScene(size: CGSize(width: 768, height: 768))
        scene.scaleMode = .aspectFit
        scene.backgroundColor = .clear
        view.presentScene(scene)
        context.coordinator.scene = scene

        apply(to: scene)
        return view
    }

    func updateUIView(_ view: SKView, context: Context) {
        if view.scene !== context.coordinator.scene, let scene = context.coordinator.scene {
            view.presentScene(scene)
        }
        guard let scene = context.coordinator.scene else { return }

        let bounds = view.bounds.size
        if bounds.width > 1, bounds.height > 1, scene.size != bounds {
            scene.size = bounds
        }
        apply(to: scene)
    }

    @available(iOS 16.0, *)
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: SKView, context: Context) -> CGSize? {
        let width = proposal.width ?? 240
        let height = proposal.height ?? width
        let side = min(width, height)
        return CGSize(width: side, height: side)
    }

    private func apply(to scene: CompanionSpriteScene) {
        let reduceMotion = !shouldAnimate
        let clip = CompanionAnimationClip.clip(for: state, reduceMotion: reduceMotion)
        scene.apply(clip: clip, generation: sequenceGeneration)
        scene.setPlaybackSuspended(!isSceneActive)
    }

    final class Coordinator {
        var scene: CompanionSpriteScene?
    }
}
