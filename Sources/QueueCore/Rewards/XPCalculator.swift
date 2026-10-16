import Foundation

/// Pure XP math — guidance-based rewards, never negative.
public struct XPBreakdown: Sendable, Equatable {
    public let baseXP: Int
    public let punctualityBonus: Int
    public let difficulty: TaskDifficulty
    public let estimatedMinutes: Int
    public let actualMinutes: Int
    /// `actual / estimate`. Values ≤ 1 mean finished within budget.
    public let budgetRatio: Double

    public var totalXP: Int { baseXP + punctualityBonus }

    public var finishedWithinBudget: Bool { budgetRatio <= 1.0 }

    public var usedSoftGrace: Bool { budgetRatio > 1.0 && punctualityBonus > 0 }
}

public enum XPCalculator {
    /// Soft grace window: slight overrun still earns a reduced on-time bonus.
    public static let softGraceRatio: Double = 1.15

    public static func breakdown(
        difficulty: TaskDifficulty,
        estimatedDuration: TimeInterval,
        actualFocusDuration: TimeInterval,
        profile: MotivationProfile = .balanced,
        config: RewardConfig = .default
    ) -> XPBreakdown {
        let estimatedMinutes = max(1, Int((estimatedDuration / 60).rounded()))
        let actualMinutes = max(0, Int((actualFocusDuration / 60).rounded()))
        let safeEstimate = max(1, estimatedDuration)
        let budgetRatio = actualFocusDuration <= 0
            ? 0
            : actualFocusDuration / safeEstimate

        // sqrt(minutes) rewards longer focus without letting tiny-task spam dominate.
        let durationFactor = sqrt(Double(estimatedMinutes)) * config.basePerSqrtMinute
        var baseXP = max(
            config.minBaseXP,
            Int((durationFactor * difficulty.xpMultiplier).rounded())
        )

        var punctualityRatio = 0.0
        if actualFocusDuration > 0 {
            if budgetRatio <= 1.0 {
                punctualityRatio = config.punctualityBonusRatio
            } else if budgetRatio <= softGraceRatio {
                punctualityRatio = config.softGraceBonusRatio
            }
        }

        var punctualityBonus = Int((Double(baseXP) * punctualityRatio).rounded())

        // Motivation profiles nudge rewards without inventing new mechanics.
        switch profile {
        case .balanced:
            break
        case .speedRunner:
            punctualityBonus = Int((Double(punctualityBonus) * 1.5).rounded())
        case .consistencyBuilder:
            // Consistency builders get a slightly higher base floor and softer punctuality.
            baseXP = Int((Double(baseXP) * 1.1).rounded())
            punctualityBonus = max(0, Int((Double(punctualityBonus) * 0.5).rounded()))
        }

        return XPBreakdown(
            baseXP: baseXP,
            punctualityBonus: punctualityBonus,
            difficulty: difficulty,
            estimatedMinutes: estimatedMinutes,
            actualMinutes: actualMinutes,
            budgetRatio: budgetRatio
        )
    }
}
