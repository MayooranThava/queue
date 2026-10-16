import Foundation

/// Visual-only companion states. Independent of timer/XP domain logic.
enum CompanionAnimationState: String, Sendable, Equatable, CaseIterable {
    case idle
    case preparing
    case working
    case deepFocus
    case paused
    case completed
    case celebrating
    case levelUp
    case timerExpired
}

/// Compatibility alias for existing Focus / Queue call sites.
typealias CompanionVisualState = CompanionAnimationState

protocol CompanionAnimationRendering {
    var state: CompanionAnimationState { get }
    var reduceMotion: Bool { get }
}
