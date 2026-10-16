import Foundation

/// Self-reported effort label. Guides XP — never used as punishment.
public enum TaskDifficulty: String, Codable, Sendable, CaseIterable, Equatable {
    case trivial
    case easy
    case medium
    case hard

    public var displayName: String {
        switch self {
        case .trivial: return "Trivial"
        case .easy: return "Easy"
        case .medium: return "Medium"
        case .hard: return "Hard"
        }
    }

    /// Multiplier for base completion XP. Harder work pays more without
    /// incentivizing fake difficulty (capped, mild curve).
    public var xpMultiplier: Double {
        switch self {
        case .trivial: return 0.6
        case .easy: return 1.0
        case .medium: return 1.35
        case .hard: return 1.8
        }
    }
}
