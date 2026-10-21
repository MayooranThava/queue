import SwiftUI

/// Motion tokens from `Docs/ANIMATION_SPEC.md`. Prefer these over magic numbers.
enum QueueMotion {
    static let quick: Animation = .easeOut(duration: 0.2)
    static let standard: Animation = .easeInOut(duration: 0.35)
    static let celebration: Animation = .spring(response: 0.55, dampingFraction: 0.78)
    static let xpCountDuration: TimeInterval = 0.8
    static let levelUpDuration: TimeInterval = 2.0
    static let queueAdvance: Animation = .easeInOut(duration: 0.45)
    /// Soft scale/fade as stack blocks enter and leave the viewport.
    static let stackScroll: Animation = .easeInOut(duration: 0.4)

    static func prefer(_ animation: Animation?, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : animation
    }
}

#if canImport(UIKit)
import UIKit

enum QueueHaptics {
    static func softTap(reduceMotion: Bool) {
        guard !reduceMotion else { return }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }

    static func success(reduceMotion: Bool) {
        guard !reduceMotion else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static let levelUp: () -> Void = {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
}
#else
enum QueueHaptics {
    static func softTap(reduceMotion: Bool) {}
    static func success(reduceMotion: Bool) {}
    static let levelUp: () -> Void = {}
}
#endif
