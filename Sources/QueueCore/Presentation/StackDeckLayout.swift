import Foundation

/// Layout math for the Queue stack deck.
///
/// Expanding, collapsing, or flipping only changes which task is shown full-size.
/// The queue order itself never changes here. Moving a task to the top stays an
/// explicit queue action owned by the caller.
public enum StackDeckLayout {
    /// Peeking task cards shown behind the expanded card before the overflow cap.
    public static let maxPeekingCards = 4
    /// Visible height of a peeking card at the default Dynamic Type size.
    public static let basePeekHeight: Double = 72
    /// Kept so older call sites can describe a hairline tuck. The deck itself
    /// overlaps by a full card minus the peek, not by this distance.
    public static let peekOverlap: Double = 8
    /// Each step further from the expanded card is this fraction of the card in front of it.
    public static let depthScaleStep: Double = 0.97
    /// Cards other than Now drop to this opacity while focus is running.
    public static let runningBackdropOpacity: Double = 0.62
    /// Stronger backdrop when Increase Contrast is on, so the titles behind Now stay readable.
    public static let runningBackdropOpacityIncreaseContrast: Double = 0.88
    public static let flipTranslationThreshold: Double = 56

    public enum Motion: Equatable, Sendable {
        /// Wallet-style spring as the expanded card grows and the others slide.
        case spring
        /// Reduce Motion, or the Reduced animation-intensity setting.
        case crossfade
    }

    public struct Card: Equatable, Sendable {
        public enum Role: Equatable, Sendable {
            /// `index` is the task's position in the unchanged queue.
            case task(index: Int)
            /// Tasks past the peek cap. `firstHiddenIndex` is the next queue position.
            case overflow(hiddenCount: Int, firstHiddenIndex: Int)
        }

        public var role: Role
        /// 0 is the expanded card. Larger values sit further back in the deck.
        public var depth: Int
        public var isExpanded: Bool

        public var taskIndex: Int? {
            if case .task(let index) = role { return index }
            return nil
        }
    }

    public static func motion(reduceMotion: Bool, allowsMotion: Bool) -> Motion {
        if reduceMotion || !allowsMotion { return .crossfade }
        return .spring
    }

    /// Top of a visible slot. Back cards are drawn at `fullHeight`; the next card
    /// starts `peekHeight` lower, so only the top strip of the card behind shows.
    /// The expanded card is the exception: the following card starts after its full height.
    public static func cardTopOffset(
        slot: Int,
        expandedSlot: Int,
        fullHeight: Double,
        peekHeight: Double
    ) -> Double {
        let full = finiteNonNegative(fullHeight)
        let peek = finiteNonNegative(peekHeight)
        let index = max(0, slot)
        let expanded = max(0, expandedSlot)
        if index <= expanded {
            return Double(index) * peek
        }
        return Double(expanded) * peek + full + Double(index - expanded - 1) * peek
    }

    /// Interpolates `cardTopOffset` while the expanded slot moves between cards.
    /// Integer values match the discrete placement. In-between values slide the
    /// full-height gap instead of jumping by a card.
    public static func cardTopOffset(
        slot: Int,
        expandedSlot: Double,
        fullHeight: Double,
        peekHeight: Double
    ) -> Double {
        let full = finiteNonNegative(fullHeight)
        let peek = finiteNonNegative(peekHeight)
        let index = max(0, slot)
        guard expandedSlot.isFinite else {
            return cardTopOffset(slot: index, expandedSlot: 0, fullHeight: full, peekHeight: peek)
        }
        let clamped = max(0, expandedSlot)
        let lower = Int(clamped.rounded(.down))
        let upper = Int(clamped.rounded(.up))
        let start = cardTopOffset(slot: index, expandedSlot: lower, fullHeight: full, peekHeight: peek)
        if lower == upper { return start }
        let end = cardTopOffset(slot: index, expandedSlot: upper, fullHeight: full, peekHeight: peek)
        return start + (end - start) * (clamped - Double(lower))
    }

    /// Visible stack height: one full card, plus a peek for every other visible slot.
    public static func visibleStackHeight(
        visibleCount: Int,
        fullHeight: Double,
        peekHeight: Double
    ) -> Double {
        guard visibleCount > 0 else { return 0 }
        let full = finiteNonNegative(fullHeight)
        let peek = finiteNonNegative(peekHeight)
        return full + peek * Double(visibleCount - 1)
    }

    /// `factor` is the Dynamic Type scale (1 at the default content size).
    public static func scaledPeekHeight(factor: Double) -> Double {
        guard factor.isFinite, factor > 0 else { return basePeekHeight }
        return basePeekHeight * factor
    }

    public static func depthScale(depth: Int) -> Double {
        let steps = max(0, depth)
        var scale = 1.0
        for _ in 0..<steps {
            scale *= depthScaleStep
        }
        return scale
    }

    /// Light mode separates cards with a soft shadow. Dark mode uses lighter surfaces instead.
    public static func showsDepthShadow(isDark: Bool) -> Bool {
        !isDark
    }

    /// How strongly to veil the surface with a lighter palette tint. 0 is the front card.
    public static func depthLightenAmount(depth: Int) -> Double {
        let steps = max(0, depth)
        return min(0.18, 0.045 * Double(steps))
    }

    public static func cardOpacity(isNowCard: Bool, focusIsRunning: Bool, increaseContrast: Bool = false) -> Double {
        guard focusIsRunning, !isNowCard else { return 1 }
        return increaseContrast ? runningBackdropOpacityIncreaseContrast : runningBackdropOpacity
    }

    /// Vertical drag maps to a deck flip. Negative travel moves to the next task.
    /// Returns 1 for next, -1 for previous, and 0 when the drag should not flip.
    public static func flipDirection(translation: Double, predicted: Double = 0) -> Int {
        let travel = abs(predicted) > abs(translation) ? predicted : translation
        if travel <= -flipTranslationThreshold { return 1 }
        if travel >= flipTranslationThreshold { return -1 }
        return 0
    }

    public static func clampedExpandedIndex(_ index: Int, taskCount: Int) -> Int {
        guard taskCount > 0 else { return 0 }
        return min(max(0, index), taskCount - 1)
    }

    public static func flippedIndex(current: Int, direction: Int, taskCount: Int) -> Int {
        clampedExpandedIndex(current + direction, taskCount: taskCount)
    }

    /// `nil` is the resting deck: the current Now card (index 0) is expanded.
    public static func expandedIndex(matching taskID: UUID?, in ids: [UUID]) -> Int {
        guard let taskID, let index = ids.firstIndex(of: taskID) else { return 0 }
        return index
    }

    /// Expanding index 0 returns `nil` so the deck rests on Now instead of pinning a stale id.
    public static func taskIDAfterExpand(index: Int, ids: [UUID]) -> UUID? {
        let next = clampedExpandedIndex(index, taskCount: ids.count)
        guard next > 0, ids.indices.contains(next) else { return nil }
        return ids[next]
    }

    public static func taskIDAfterFlip(from expandedTaskID: UUID?, ids: [UUID], direction: Int) -> UUID? {
        let current = expandedIndex(matching: expandedTaskID, in: ids)
        let next = flippedIndex(current: current, direction: direction, taskCount: ids.count)
        guard next > 0, ids.indices.contains(next) else { return nil }
        return ids[next]
    }

    /// Visible deck, top to bottom, in queue order.
    ///
    /// The resting deck is Now, up to four peeking cards, then one "+N more" card.
    /// Expanding a card inside that window grows it in place. Past the window, the
    /// expanded task leads and up to four cards behind it peek.
    public static func cards(taskCount: Int, expandedIndex: Int) -> [Card] {
        guard taskCount > 0 else { return [] }
        let expanded = clampedExpandedIndex(expandedIndex, taskCount: taskCount)
        let windowStart = expanded <= maxPeekingCards ? 0 : expanded
        let windowEnd = min(taskCount, windowStart + 1 + maxPeekingCards)
        var cards: [Card] = []
        for index in windowStart..<windowEnd {
            cards.append(
                Card(
                    role: .task(index: index),
                    depth: abs(index - expanded),
                    isExpanded: index == expanded
                )
            )
        }
        let hidden = taskCount - windowEnd
        if hidden > 0 {
            cards.append(
                Card(
                    role: .overflow(hiddenCount: hidden, firstHiddenIndex: windowEnd),
                    depth: max(abs(windowEnd - expanded), 1),
                    isExpanded: false
                )
            )
        }
        return cards
    }

    public static func visibleTaskIndices(taskCount: Int, expandedIndex: Int) -> [Int] {
        cards(taskCount: taskCount, expandedIndex: expandedIndex).compactMap(\.taskIndex)
    }

    public static func accessibilityLabel(position: Int, total: Int, title: String, detail: String) -> String {
        "Task \(position) of \(total), \(title), \(detail)"
    }

    public static func overflowTitle(hiddenCount: Int) -> String {
        "+\(hiddenCount) more"
    }

    public static func overflowAccessibilityLabel(hiddenCount: Int) -> String {
        hiddenCount == 1 ? "1 more task" : "\(hiddenCount) more tasks"
    }

    private static func finiteNonNegative(_ value: Double) -> Double {
        guard value.isFinite, value > 0 else { return 0 }
        return value
    }
}
