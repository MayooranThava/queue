import SwiftUI

/// Production companion entry point backed by SpriteKit atlas playback.
/// Design frames are 768×768 PNG sequences in `Working` / `DeepFocus` / `Completed` / `Expired` atlases.
struct CompanionAnimationView: View, CompanionAnimationRendering {
    let state: CompanionAnimationState
    let reduceMotion: Bool
    var compact: Bool = false

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var sequenceGeneration: UInt = 0

    private var shouldAnimate: Bool {
        !reduceMotion && !systemReduceMotion
    }

    var body: some View {
        CompanionSpriteView(
            state: state,
            shouldAnimate: shouldAnimate,
            isSceneActive: scenePhase == .active,
            sequenceGeneration: sequenceGeneration
        )
        .aspectRatio(1, contentMode: .fit)
        // Parent Focus transitions must not fade/scale the SKView (empty-frame flash).
        .transaction { $0.animation = nil }
        .allowsHitTesting(false)
        .accessibilityLabel(accessibilityLabel)
        .onAppear {
            CompanionTextureStore.shared.preloadIfNeeded()
        }
        .onChange(of: state) { _, _ in
            sequenceGeneration &+= 1
        }
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
#Preview("Idle / Reduce Motion") {
    CompanionAnimationView(state: .idle, reduceMotion: true)
        .frame(width: 240, height: 240)
        .background(QueueColors.charcoal)
}
#endif
