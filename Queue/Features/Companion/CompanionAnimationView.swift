import SwiftUI
import UIKit

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
        GeometryReader { geo in
            let side = max(1, min(geo.size.width, geo.size.height))
            ZStack {
                // Asset-catalog still as a first paint so Focus never looks empty
                // while SpriteKit attaches (or if Metal is briefly unavailable).
                CompanionStillImage(state: state)
                    .frame(width: side, height: side)

                CompanionSpriteView(
                    state: state,
                    shouldAnimate: shouldAnimate,
                    isSceneActive: scenePhase == .active,
                    sequenceGeneration: sequenceGeneration
                )
                .frame(width: side, height: side)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
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

/// SwiftUI image fallback from the same atlas frames (asset catalog).
private struct CompanionStillImage: View {
    let state: CompanionAnimationState

    var body: some View {
        let name = stillFrameName(for: state)
        if UIImage(named: name) != nil {
            Image(name)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
        } else {
            Color.clear
        }
    }

    private func stillFrameName(for state: CompanionAnimationState) -> String {
        switch state {
        case .working, .preparing:
            return "working_000"
        case .deepFocus:
            return "deepfocus_000"
        case .paused, .idle:
            return "working_006"
        case .completed, .celebrating, .levelUp:
            return "completed_011"
        case .timerExpired:
            return "expired_011"
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
