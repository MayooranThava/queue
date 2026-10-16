import Testing
import Foundation
@testable import QueueCore

@Suite("RewardEngine")
struct RewardEngineTests {
    @Test("Awards completion XP once")
    func idempotentAward() async {
        let engine = RewardEngine(clock: ControllableClock())
        let source = UUID()
        let taskID = UUID()
        let first = await engine.awardTaskCompletion(
            sourceEventID: source,
            taskID: taskID,
            difficulty: .easy,
            estimatedDuration: 600,
            actualFocusDuration: 500
        )
        let second = await engine.awardTaskCompletion(
            sourceEventID: source,
            taskID: taskID,
            difficulty: .easy,
            estimatedDuration: 600,
            actualFocusDuration: 500
        )
        #expect(first.awardedXP == first.breakdown.totalXP)
        #expect(first.breakdown.baseXP > 0)
        #expect(first.breakdown.punctualityBonus > 0)
        #expect(second.awardedXP == 0)
        #expect(await engine.totalXP() == first.awardedXP)
    }

    @Test("Over-budget finishes still earn base XP, not negative")
    func overBudgetNoPenalty() async {
        let engine = RewardEngine(clock: ControllableClock())
        let result = await engine.awardTaskCompletion(
            sourceEventID: UUID(),
            taskID: UUID(),
            difficulty: .hard,
            estimatedDuration: 15 * 60,
            actualFocusDuration: 40 * 60
        )
        #expect(result.breakdown.baseXP > 0)
        #expect(result.breakdown.punctualityBonus == 0)
        #expect(result.awardedXP == result.breakdown.baseXP)
        #expect(result.awardedXP > 0)
    }

    @Test("Harder tasks award more base XP than trivial ones")
    func difficultyScalesBase() async {
        let engineEasy = RewardEngine(clock: ControllableClock())
        let engineHard = RewardEngine(clock: ControllableClock())
        let easy = await engineEasy.awardTaskCompletion(
            sourceEventID: UUID(),
            taskID: UUID(),
            difficulty: .trivial,
            estimatedDuration: 25 * 60,
            actualFocusDuration: 40 * 60
        )
        let hard = await engineHard.awardTaskCompletion(
            sourceEventID: UUID(),
            taskID: UUID(),
            difficulty: .hard,
            estimatedDuration: 25 * 60,
            actualFocusDuration: 40 * 60
        )
        #expect(hard.breakdown.baseXP > easy.breakdown.baseXP)
    }

    @Test("Soft grace keeps a reduced punctuality bonus")
    func softGrace() {
        let onTime = XPCalculator.breakdown(
            difficulty: .medium,
            estimatedDuration: 20 * 60,
            actualFocusDuration: 20 * 60
        )
        let grace = XPCalculator.breakdown(
            difficulty: .medium,
            estimatedDuration: 20 * 60,
            actualFocusDuration: 22 * 60
        )
        let late = XPCalculator.breakdown(
            difficulty: .medium,
            estimatedDuration: 20 * 60,
            actualFocusDuration: 30 * 60
        )
        #expect(onTime.punctualityBonus > grace.punctualityBonus)
        #expect(grace.punctualityBonus > 0)
        #expect(late.punctualityBonus == 0)
    }

    @Test("Level crossings")
    func multiLevel() async {
        let levels = [
            LevelDefinition(name: "A", minimumXP: 0),
            LevelDefinition(name: "B", minimumXP: 40),
            LevelDefinition(name: "C", minimumXP: 80)
        ]
        let engine = RewardEngine(
            clock: ControllableClock(),
            config: RewardConfig(
                basePerSqrtMinute: 100,
                minBaseXP: 100,
                punctualityBonusRatio: 0,
                softGraceBonusRatio: 0,
                dailyGoalXP: 0,
                streakMilestoneXP: 0
            ),
            levels: levels
        )
        let result = await engine.awardTaskCompletion(
            sourceEventID: UUID(),
            taskID: UUID(),
            estimatedDuration: 100,
            actualFocusDuration: 200
        )
        #expect(result.levelsCrossed.map(\.name) == ["B", "C"])
    }

    @Test("Speed runner boosts on-time bonus")
    func speedRunner() async {
        let balanced = RewardEngine(clock: ControllableClock(), profile: .balanced)
        let speed = RewardEngine(clock: ControllableClock(), profile: .speedRunner)
        let balancedResult = await balanced.awardTaskCompletion(
            sourceEventID: UUID(),
            taskID: UUID(),
            difficulty: .easy,
            estimatedDuration: 10 * 60,
            actualFocusDuration: 9 * 60
        )
        let speedResult = await speed.awardTaskCompletion(
            sourceEventID: UUID(),
            taskID: UUID(),
            difficulty: .easy,
            estimatedDuration: 10 * 60,
            actualFocusDuration: 9 * 60
        )
        #expect(speedResult.breakdown.punctualityBonus > balancedResult.breakdown.punctualityBonus)
    }
}
