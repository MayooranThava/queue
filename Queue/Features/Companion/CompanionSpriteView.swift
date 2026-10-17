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

        let view = SKView(frame: .zero)
        view.allowsTransparency = true
        view.isOpaque = false
        view.backgroundColor = .clear
        view.ignoresSiblingOrder = true
        #if DEBUG
        view.showsFPS = false
        view.showsNodeCount = false
        #endif

        let scene = CompanionSpriteScene(size: CGSize(width: 768, height: 768))
        scene.scaleMode = .aspectFit
        view.presentScene(scene)
        context.coordinator.scene = scene

        apply(to: scene)
        return view
    }

    func updateUIView(_ view: SKView, context: Context) {
        // Intentionally do not call `presentScene` again — that would flash / reset.
        if view.scene !== context.coordinator.scene, let scene = context.coordinator.scene {
            view.presentScene(scene)
        }
        guard let scene = context.coordinator.scene else { return }

        if view.bounds.size != .zero, scene.size != view.bounds.size {
            scene.size = view.bounds.size
        }
        apply(to: scene)
    }

    private func apply(to scene: CompanionSpriteScene) {
        let reduceMotion = !shouldAnimate
        let clip = CompanionAnimationClip.clip(for: state, reduceMotion: reduceMotion)
        scene.apply(clip: clip, generation: sequenceGeneration)
        // Suspend when backgrounded; Reduce Motion already uses a static clip.
        scene.setPlaybackSuspended(!isSceneActive)
    }

    final class Coordinator {
        var scene: CompanionSpriteScene?
    }
}
