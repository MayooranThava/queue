import Testing
@testable import QueueCore

@Suite("Level bar sequence")
struct LevelBarSequenceTests {
    @Test("No level-up animates forward on the same level")
    func sameLevelFillsForward() {
        let segments = LevelBarSequence.segments(from: 215, to: 280)
        let origin = LevelTable.progress(towardNext: 215)
        let destination = LevelTable.progress(towardNext: 280)

        #expect(segments.count == 1)
        #expect(segments[0].currentLevel == origin.current)
        #expect(segments[0].nextLevel == origin.next)
        #expect(segments[0].currentLevel.name == "Builder")
        #expect(segments[0].nextLevel?.name == "Momentum Maker")
        #expect(segments[0].startFraction == origin.fraction)
        #expect(segments[0].endFraction == destination.fraction)
        #expect(segments[0].endFraction > segments[0].startFraction)
        #expect(!segments[0].resetAfter)
        expectForwardPlayback(segments)
    }

    @Test("Unchanged XP holds the current fill")
    func unchangedXP() {
        let segments = LevelBarSequence.segments(from: 215, to: 215)
        let progress = LevelTable.progress(towardNext: 215)
        #expect(segments.count == 1)
        #expect(segments[0].startFraction == progress.fraction)
        #expect(segments[0].endFraction == progress.fraction)
        #expect(!segments[0].resetAfter)
        expectForwardPlayback(segments)
    }

    @Test("Level-up into Builder fills the old level before the new one")
    func levelUpDoesNotPlayBackwards() {
        // Medium · 20 min · on-time awards 65 XP. 150 → 215 crosses into Builder
        // with the new bar nearly empty — the celebration that used to shrink.
        let segments = LevelBarSequence.segments(from: 150, to: 215)
        let origin = LevelTable.progress(towardNext: 150)
        let destination = LevelTable.progress(towardNext: 215)

        #expect(segments.count == 2)
        #expect(segments[0].currentLevel.name == "Starter")
        #expect(segments[0].nextLevel?.name == "Builder")
        #expect(segments[0].startFraction == origin.fraction)
        #expect(segments[0].startFraction == 0.75)
        #expect(segments[0].endFraction == 1)
        #expect(segments[0].resetAfter)

        #expect(segments[1].currentLevel == destination.current)
        #expect(segments[1].currentLevel.name == "Builder")
        #expect(segments[1].nextLevel?.name == "Momentum Maker")
        #expect(segments[1].startFraction == 0)
        #expect(segments[1].endFraction == destination.fraction)
        #expect(segments[1].endFraction < segments[0].startFraction)
        #expect(!segments[1].resetAfter)
        expectForwardPlayback(segments)
    }

    @Test("Landing exactly on a threshold ends empty on the new level")
    func exactThreshold() {
        let segments = LevelBarSequence.segments(from: 150, to: 200)
        let destination = LevelTable.progress(towardNext: 200)

        #expect(segments.count == 2)
        #expect(segments[0].endFraction == 1)
        #expect(segments[0].resetAfter)
        #expect(segments[1].currentLevel == destination.current)
        #expect(segments[1].currentLevel.name == "Builder")
        #expect(segments[1].nextLevel?.name == "Momentum Maker")
        #expect(segments[1].startFraction == 0)
        #expect(segments[1].endFraction == 0)
        #expect(!segments[1].resetAfter)
        expectForwardPlayback(segments)
    }

    @Test("Several levels crossed each fill to full and then reset")
    func multiLevel() {
        let segments = LevelBarSequence.segments(from: 150, to: 1500)
        let destination = LevelTable.progress(towardNext: 1500)

        #expect(segments.map { "\($0.currentLevel.name)→\($0.nextLevel?.name ?? "max")" } == [
            "Starter→Builder",
            "Builder→Momentum Maker",
            "Momentum Maker→Focus Pro",
            "Focus Pro→Queue Master"
        ])
        #expect(segments.dropLast().allSatisfy { $0.endFraction == 1 && $0.resetAfter })
        #expect(segments.last?.currentLevel == destination.current)
        #expect(segments.last?.nextLevel == destination.next)
        #expect(segments.last?.startFraction == 0)
        #expect(segments.last?.endFraction == destination.fraction)
        #expect(segments.last?.resetAfter == false)
        expectForwardPlayback(segments)
    }

    @Test("Crossing several levels and landing on a threshold ends empty there")
    func multiLevelExact() {
        let segments = LevelBarSequence.segments(from: 150, to: 600)
        #expect(segments.count == 3)
        #expect(segments[0].currentLevel.name == "Starter")
        #expect(segments[1].currentLevel.name == "Builder")
        #expect(segments[1].endFraction == 1)
        #expect(segments[1].resetAfter)
        #expect(segments[2].currentLevel.name == "Momentum Maker")
        #expect(segments[2].nextLevel?.name == "Focus Pro")
        #expect(segments[2].startFraction == 0)
        #expect(segments[2].endFraction == 0)
        expectForwardPlayback(segments)
    }

    @Test("Reaching the max level fills it after the previous level completes")
    func reachingMaxLevel() {
        let segments = LevelBarSequence.segments(from: 2900, to: 3100)
        let origin = LevelTable.progress(towardNext: 2900)
        let destination = LevelTable.progress(towardNext: 3100)

        #expect(segments.count == 2)
        #expect(segments[0].currentLevel == origin.current)
        #expect(segments[0].currentLevel.name == "Focus Pro")
        #expect(segments[0].nextLevel?.name == "Queue Master")
        #expect(segments[0].startFraction == origin.fraction)
        #expect(segments[0].endFraction == 1)
        #expect(segments[0].resetAfter)
        #expect(segments[1].currentLevel == destination.current)
        #expect(segments[1].currentLevel.name == "Queue Master")
        #expect(segments[1].nextLevel == nil)
        #expect(segments[1].startFraction == 0)
        #expect(segments[1].endFraction == 1)
        #expect(!segments[1].resetAfter)
        expectForwardPlayback(segments)
    }

    @Test("XP gained at the max level stays full")
    func alreadyMaxLevel() {
        let segments = LevelBarSequence.segments(from: 3100, to: 3200)
        #expect(segments.count == 1)
        #expect(segments[0].currentLevel.name == "Queue Master")
        #expect(segments[0].nextLevel == nil)
        #expect(segments[0].startFraction == 1)
        #expect(segments[0].endFraction == 1)
        #expect(!segments[0].resetAfter)
        expectForwardPlayback(segments)
    }

    @Test("A drop in XP cuts to the destination instead of rewinding")
    func xpDecreaseDoesNotRewind() {
        let segments = LevelBarSequence.segments(from: 800, to: 150)
        let destination = LevelTable.progress(towardNext: 150)
        #expect(segments.count == 1)
        #expect(segments[0].currentLevel == destination.current)
        #expect(segments[0].nextLevel == destination.next)
        #expect(segments[0].startFraction == destination.fraction)
        #expect(segments[0].endFraction == destination.fraction)
        #expect(!segments[0].resetAfter)
        expectForwardPlayback(segments)
    }

    @Test("From zero with no level-up starts empty and fills forward")
    func fromZero() {
        let segments = LevelBarSequence.segments(from: 0, to: 50)
        let destination = LevelTable.progress(towardNext: 50)
        #expect(segments.count == 1)
        #expect(segments[0].currentLevel.name == "Starter")
        #expect(segments[0].startFraction == 0)
        #expect(segments[0].endFraction == destination.fraction)
        #expect(segments[0].endFraction > 0)
        #expect(!segments[0].resetAfter)
        expectForwardPlayback(segments)
    }

    @Test("Negative XP is treated as zero")
    func negativeXPClamped() {
        #expect(
            LevelBarSequence.segments(from: -20, to: 40)
                == LevelBarSequence.segments(from: 0, to: 40)
        )
    }

    @Test("Custom unsorted tables still fill each crossed level")
    func customTable() {
        let table = [
            LevelDefinition(name: "C", minimumXP: 20),
            LevelDefinition(name: "A", minimumXP: 0),
            LevelDefinition(name: "D", minimumXP: 30),
            LevelDefinition(name: "B", minimumXP: 10)
        ]
        let segments = LevelBarSequence.segments(from: 5, to: 25, table: table)
        let destination = LevelTable.progress(towardNext: 25, table: table)

        #expect(segments.map(\.currentLevel.name) == ["A", "B", "C"])
        #expect(segments.map { $0.nextLevel?.name } == ["B", "C", "D"])
        #expect(segments[0].startFraction == 0.5)
        #expect(segments[0].endFraction == 1)
        #expect(segments[1].startFraction == 0)
        #expect(segments[1].endFraction == 1)
        #expect(segments[2].startFraction == 0)
        #expect(segments[2].endFraction == destination.fraction)
        #expect(segments[2].endFraction == 0.5)
        expectForwardPlayback(segments)
    }

    private func expectForwardPlayback(
        _ segments: [LevelBarSegment],
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        #expect(!segments.isEmpty, sourceLocation: sourceLocation)
        for (index, segment) in segments.enumerated() {
            #expect(segment.startFraction >= 0, sourceLocation: sourceLocation)
            #expect(segment.endFraction <= 1, sourceLocation: sourceLocation)
            #expect(segment.endFraction >= segment.startFraction, sourceLocation: sourceLocation)
            if segment.resetAfter {
                #expect(segment.nextLevel != nil, sourceLocation: sourceLocation)
                #expect(segment.endFraction == 1, sourceLocation: sourceLocation)
            }
            guard index > 0 else { continue }
            let previous = segments[index - 1]
            if previous.resetAfter {
                #expect(segment.startFraction == 0, sourceLocation: sourceLocation)
                #expect(segment.currentLevel == previous.nextLevel, sourceLocation: sourceLocation)
            } else {
                #expect(segment.startFraction >= previous.endFraction, sourceLocation: sourceLocation)
            }
        }
        #expect(segments.last?.resetAfter == false, sourceLocation: sourceLocation)
    }
}
