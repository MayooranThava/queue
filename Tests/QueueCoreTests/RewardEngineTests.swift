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
            estimatedDuration: 600,
            actualFocusDuration: 500
        )
        let second = await engine.awardTaskCompletion(
            sourceEventID: source,
            taskID: taskID,
            estimatedDuration: 600,
            actualFocusDuration: 500
        )
        #expect(first.awardedXP == 70) // 50 + 20
        #expect(second.awardedXP == 0)
        #expect(await engine.totalXP() == 70)
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
                taskCompletedXP: 100,
                withinEstimateXP: 0,
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
        let engine = RewardEngine(
            clock: ControllableClock(),
            profile: .speedRunner
        )
        let result = await engine.awardTaskCompletion(
            sourceEventID: UUID(),
            taskID: UUID(),
            estimatedDuration: 100,
            actualFocusDuration: 90
        )
        #expect(result.awardedXP == 50 + 30) // 20 * 1.5
    }
}
