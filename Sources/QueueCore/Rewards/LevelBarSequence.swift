import Foundation

/// One forward fill of the celebration XP bar.
///
/// `endFraction` is always at least `startFraction`. A level change is not a
/// fill from the old fraction down to the new one: `resetAfter` means the
/// player snaps to empty (and to the next segment's labels) before continuing.
public struct LevelBarSegment: Sendable, Equatable {
    public let currentLevel: LevelDefinition
    public let nextLevel: LevelDefinition?
    /// Bar fill at the start of this segment, in `0...1`.
    public let startFraction: Double
    /// Bar fill at the end of this segment, in `startFraction...1`.
    public let endFraction: Double
    /// When true, the level was just completed. Snap to empty before the next
    /// segment instead of interpolating toward it.
    public let resetAfter: Bool

    public init(
        currentLevel: LevelDefinition,
        nextLevel: LevelDefinition?,
        startFraction: Double,
        endFraction: Double,
        resetAfter: Bool
    ) {
        self.currentLevel = currentLevel
        self.nextLevel = nextLevel
        self.startFraction = startFraction
        self.endFraction = endFraction
        self.resetAfter = resetAfter
    }
}

/// Sequence of XP-bar segments for the task-completion celebration.
public enum LevelBarSequence {
    /// Segments that play `previousXP` → `newXP` without a backwards fill.
    ///
    /// No level-up yields a single forward fill on the current level. Each
    /// level crossed yields a fill to full, then a later segment that starts
    /// empty on the level just entered. Several levels crossed repeat that
    /// fill-and-reset once per level. If XP did not increase, the sequence is
    /// a single cut to the destination so the bar never rewinds.
    public static func segments(
        from previousXP: Int,
        to newXP: Int,
        table: [LevelDefinition] = LevelTable.standard
    ) -> [LevelBarSegment] {
        let fromXP = max(0, previousXP)
        let toXP = max(0, newXP)
        let sorted = table.sorted { $0.minimumXP < $1.minimumXP }
        let destination = LevelTable.progress(towardNext: toXP, table: sorted)

        if toXP < fromXP {
            return [
                makeSegment(
                    current: destination.current,
                    next: destination.next,
                    from: destination.fraction,
                    to: destination.fraction,
                    resetAfter: false
                )
            ]
        }

        let origin = LevelTable.progress(towardNext: fromXP, table: sorted)
        let crossed = LevelTable.levelsCrossed(from: fromXP, to: toXP, table: sorted)
        guard !crossed.isEmpty else {
            return [
                makeSegment(
                    current: origin.current,
                    next: origin.next,
                    from: origin.fraction,
                    to: destination.fraction,
                    resetAfter: false
                )
            ]
        }

        var segments: [LevelBarSegment] = []
        var currentLevel = origin.current
        var nextLevel = origin.next
        var startFraction = origin.fraction

        for crossedLevel in crossed {
            segments.append(
                makeSegment(
                    current: currentLevel,
                    next: nextLevel ?? crossedLevel,
                    from: startFraction,
                    to: 1,
                    resetAfter: true
                )
            )
            currentLevel = crossedLevel
            nextLevel = levelFollowing(crossedLevel, in: sorted)
            startFraction = 0
        }

        segments.append(
            makeSegment(
                current: destination.current,
                next: destination.next,
                from: 0,
                to: destination.fraction,
                resetAfter: false
            )
        )
        return segments
    }

    private static func makeSegment(
        current: LevelDefinition,
        next: LevelDefinition?,
        from start: Double,
        to end: Double,
        resetAfter: Bool
    ) -> LevelBarSegment {
        let clampedStart = min(1, max(0, start))
        let clampedEnd = min(1, max(clampedStart, end))
        return LevelBarSegment(
            currentLevel: current,
            nextLevel: next,
            startFraction: clampedStart,
            endFraction: clampedEnd,
            resetAfter: resetAfter
        )
    }

    private static func levelFollowing(
        _ level: LevelDefinition,
        in sorted: [LevelDefinition]
    ) -> LevelDefinition? {
        let index = sorted.firstIndex {
            $0.name == level.name && $0.minimumXP == level.minimumXP
        } ?? sorted.firstIndex { $0.minimumXP == level.minimumXP }
        guard let index else {
            return sorted.first { $0.minimumXP > level.minimumXP }
        }
        let next = sorted.index(after: index)
        guard next < sorted.endIndex else { return nil }
        return sorted[next]
    }
}
