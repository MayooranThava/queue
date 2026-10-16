import Foundation

public enum MotivationProfile: String, Codable, Sendable, CaseIterable {
    case balanced
    case speedRunner
    case consistencyBuilder
}

public enum RewardType: String, Codable, Sendable, CaseIterable {
    case taskCompleted
    case completedWithinEstimate
    case dailyGoal
    case streakMilestone
}

public struct RewardConfig: Sendable, Equatable {
    /// Scales with `sqrt(estimatedMinutes)` for base completion XP.
    public var basePerSqrtMinute: Double
    public var minBaseXP: Int
    /// Fraction of base XP awarded when finishing within estimate.
    public var punctualityBonusRatio: Double
    /// Fraction of base XP awarded when slightly over budget (≤ soft grace).
    public var softGraceBonusRatio: Double
    public var dailyGoalXP: Int
    public var streakMilestoneXP: Int

    public static let `default` = RewardConfig(
        basePerSqrtMinute: 8,
        minBaseXP: 15,
        punctualityBonusRatio: 0.35,
        softGraceBonusRatio: 0.15,
        dailyGoalXP: 40,
        streakMilestoneXP: 30
    )

    public init(
        basePerSqrtMinute: Double,
        minBaseXP: Int,
        punctualityBonusRatio: Double,
        softGraceBonusRatio: Double,
        dailyGoalXP: Int,
        streakMilestoneXP: Int
    ) {
        self.basePerSqrtMinute = basePerSqrtMinute
        self.minBaseXP = minBaseXP
        self.punctualityBonusRatio = punctualityBonusRatio
        self.softGraceBonusRatio = softGraceBonusRatio
        self.dailyGoalXP = dailyGoalXP
        self.streakMilestoneXP = streakMilestoneXP
    }
}

public struct XPTransaction: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public let sourceEventID: UUID
    public let taskID: UUID?
    public let rewardType: RewardType
    public let amount: Int
    public let timestamp: Date

    public init(
        id: UUID = UUID(),
        sourceEventID: UUID,
        taskID: UUID? = nil,
        rewardType: RewardType,
        amount: Int,
        timestamp: Date
    ) {
        self.id = id
        self.sourceEventID = sourceEventID
        self.taskID = taskID
        self.rewardType = rewardType
        self.amount = amount
        self.timestamp = timestamp
    }
}

public struct LevelDefinition: Sendable, Equatable, Identifiable {
    public var id: String { name }
    public let name: String
    public let minimumXP: Int

    public init(name: String, minimumXP: Int) {
        self.name = name
        self.minimumXP = minimumXP
    }
}

public enum LevelTable {
    public static let standard: [LevelDefinition] = [
        .init(name: "Starter", minimumXP: 0),
        .init(name: "Builder", minimumXP: 200),
        .init(name: "Momentum Maker", minimumXP: 600),
        .init(name: "Focus Pro", minimumXP: 1400),
        .init(name: "Queue Master", minimumXP: 3000)
    ]

    public static func level(forXP xp: Int, table: [LevelDefinition] = standard) -> LevelDefinition {
        let sorted = table.sorted { $0.minimumXP < $1.minimumXP }
        var current = sorted.first ?? LevelDefinition(name: "Starter", minimumXP: 0)
        for level in sorted where xp >= level.minimumXP {
            current = level
        }
        return current
    }

    public static func levelsCrossed(
        from previousXP: Int,
        to newXP: Int,
        table: [LevelDefinition] = standard
    ) -> [LevelDefinition] {
        table
            .sorted { $0.minimumXP < $1.minimumXP }
            .filter { $0.minimumXP > previousXP && $0.minimumXP <= newXP }
    }

    public static func progress(towardNext levelXP: Int, table: [LevelDefinition] = standard) -> (
        current: LevelDefinition,
        next: LevelDefinition?,
        fraction: Double
    ) {
        let current = level(forXP: levelXP, table: table)
        let sorted = table.sorted { $0.minimumXP < $1.minimumXP }
        let next = sorted.first { $0.minimumXP > current.minimumXP }
        guard let next else {
            return (current, nil, 1)
        }
        let span = Double(next.minimumXP - current.minimumXP)
        guard span > 0 else { return (current, next, 1) }
        let fraction = Double(levelXP - current.minimumXP) / span
        return (current, next, min(1, max(0, fraction)))
    }
}

public struct RewardAwardResult: Sendable, Equatable {
    public let transactions: [XPTransaction]
    public let totalXP: Int
    public let previousXP: Int
    public let levelsCrossed: [LevelDefinition]
    public let breakdown: XPBreakdown

    public var awardedXP: Int {
        transactions.reduce(0) { $0 + $1.amount }
    }
}

/// Deterministic, idempotent XP ledger.
public actor RewardEngine {
    private var ledger: [XPTransaction]
    private var seenKeys: Set<String>
    private var config: RewardConfig
    private var profile: MotivationProfile
    private let clock: any QueueClock
    private let levels: [LevelDefinition]

    public init(
        clock: any QueueClock = SystemQueueClock(),
        config: RewardConfig = .default,
        profile: MotivationProfile = .balanced,
        levels: [LevelDefinition] = LevelTable.standard,
        transactions: [XPTransaction] = []
    ) {
        self.clock = clock
        self.config = config
        self.profile = profile
        self.levels = levels
        self.ledger = transactions
        self.seenKeys = Set(transactions.map { Self.key(source: $0.sourceEventID, type: $0.rewardType) })
    }

    public func totalXP() -> Int {
        ledger.reduce(0) { $0 + $1.amount }
    }

    public func transactions() -> [XPTransaction] {
        ledger.sorted { $0.timestamp < $1.timestamp }
    }

    public func setProfile(_ profile: MotivationProfile) {
        self.profile = profile
    }

    /// Replaces the in-memory ledger with persisted transactions (bootstrap).
    public func restore(transactions: [XPTransaction]) {
        ledger = transactions
        seenKeys = Set(transactions.map { Self.key(source: $0.sourceEventID, type: $0.rewardType) })
    }

    public func awardTaskCompletion(
        sourceEventID: UUID,
        taskID: UUID,
        difficulty: TaskDifficulty = .medium,
        estimatedDuration: TimeInterval,
        actualFocusDuration: TimeInterval,
        dailyGoalMet: Bool = false
    ) -> RewardAwardResult {
        let previous = totalXP()
        var created: [XPTransaction] = []
        let breakdown = XPCalculator.breakdown(
            difficulty: difficulty,
            estimatedDuration: estimatedDuration,
            actualFocusDuration: actualFocusDuration,
            profile: profile,
            config: config
        )

        if let tx = insert(
            sourceEventID: sourceEventID,
            taskID: taskID,
            type: .taskCompleted,
            amount: breakdown.baseXP
        ) {
            created.append(tx)
        }

        if breakdown.punctualityBonus > 0 {
            if let tx = insert(
                sourceEventID: sourceEventID,
                taskID: taskID,
                type: .completedWithinEstimate,
                amount: breakdown.punctualityBonus
            ) {
                created.append(tx)
            }
        }

        if dailyGoalMet {
            if let tx = insert(
                sourceEventID: sourceEventID,
                taskID: taskID,
                type: .dailyGoal,
                amount: config.dailyGoalXP
            ) {
                created.append(tx)
            }
        }

        let newTotal = totalXP()
        return RewardAwardResult(
            transactions: created,
            totalXP: newTotal,
            previousXP: previous,
            levelsCrossed: LevelTable.levelsCrossed(from: previous, to: newTotal, table: levels),
            breakdown: breakdown
        )
    }

    private func insert(
        sourceEventID: UUID,
        taskID: UUID?,
        type: RewardType,
        amount: Int
    ) -> XPTransaction? {
        let key = Self.key(source: sourceEventID, type: type)
        guard !seenKeys.contains(key) else { return nil }
        guard amount > 0 else { return nil }
        let tx = XPTransaction(
            sourceEventID: sourceEventID,
            taskID: taskID,
            rewardType: type,
            amount: amount,
            timestamp: clock.now()
        )
        seenKeys.insert(key)
        ledger.append(tx)
        return tx
    }

    private static func key(source: UUID, type: RewardType) -> String {
        "\(source.uuidString)|\(type.rawValue)"
    }
}
