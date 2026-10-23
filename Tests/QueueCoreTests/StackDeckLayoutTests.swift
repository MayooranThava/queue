import Testing
import Foundation
@testable import QueueCore

@Suite("Stack deck layout")
struct StackDeckLayoutTests {
    @Test("Resting deck shows Now, four peeks, then one overflow card")
    func restingWindow() {
        let cards = StackDeckLayout.cards(taskCount: 9, expandedIndex: 0)
        #expect(cards.compactMap(\.taskIndex) == [0, 1, 2, 3, 4])
        #expect(cards.filter(\.isExpanded).compactMap(\.taskIndex) == [0])
        #expect(cards.map(\.depth) == [0, 1, 2, 3, 4, 5])
        guard case .overflow(let hidden, let first) = cards.last?.role else {
            Issue.record("Expected a trailing overflow card")
            return
        }
        #expect(hidden == 4)
        #expect(first == 5)
        #expect(StackDeckLayout.overflowTitle(hiddenCount: hidden) == "+4 more")
        #expect(StackDeckLayout.overflowAccessibilityLabel(hiddenCount: hidden) == "4 more tasks")
    }

    @Test("Five tasks need no overflow card")
    func fiveTasksFit() {
        let cards = StackDeckLayout.cards(taskCount: 5, expandedIndex: 0)
        #expect(cards.count == 5)
        #expect(cards.allSatisfy { $0.taskIndex != nil })
    }

    @Test("The sixth task collapses into +1 more")
    func sixthTaskOverflows() {
        let cards = StackDeckLayout.cards(taskCount: 6, expandedIndex: 0)
        guard case .overflow(let hidden, let first) = cards.last?.role else {
            Issue.record("Expected overflow")
            return
        }
        #expect(hidden == 1)
        #expect(first == 5)
        #expect(StackDeckLayout.overflowTitle(hiddenCount: 1) == "+1 more")
        #expect(StackDeckLayout.overflowAccessibilityLabel(hiddenCount: 1) == "1 more task")
    }

    @Test("Expanding a peek keeps queue order and grows that card in place")
    func expandInPlace() {
        let before = StackDeckLayout.visibleTaskIndices(taskCount: 8, expandedIndex: 0)
        let after = StackDeckLayout.visibleTaskIndices(taskCount: 8, expandedIndex: 2)
        #expect(before == [0, 1, 2, 3, 4])
        #expect(after == [0, 1, 2, 3, 4])
        let cards = StackDeckLayout.cards(taskCount: 8, expandedIndex: 2)
        #expect(cards.filter(\.isExpanded).compactMap(\.taskIndex) == [2])
        let depthByIndex = Dictionary(
            uniqueKeysWithValues: cards.compactMap { card -> (Int, Int)? in
                guard let index = card.taskIndex else { return nil }
                return (index, card.depth)
            }
        )
        #expect(depthByIndex[2] == .some(0))
        #expect(depthByIndex[1] == .some(1))
        #expect(depthByIndex[3] == .some(1))
    }

    @Test("Every expansion stays in ascending queue order")
    func expansionsStayOrdered() {
        for count in 0...12 {
            let upper = max(count, 1)
            for expanded in 0..<upper {
                let cards = StackDeckLayout.cards(taskCount: count, expandedIndex: expanded)
                let indices = cards.compactMap(\.taskIndex)
                #expect(indices == indices.sorted())
                #expect(Set(indices).count == indices.count)
                #expect(indices.allSatisfy { $0 >= 0 && $0 < count })
                let peekCount = cards.filter { !$0.isExpanded && $0.taskIndex != nil }.count
                #expect(peekCount <= StackDeckLayout.maxPeekingCards)
                let overflowCount = cards.filter {
                    if case .overflow = $0.role { return true }
                    return false
                }.count
                #expect(overflowCount <= 1)
                if count == 0 {
                    #expect(cards.isEmpty)
                } else {
                    let expandedCards = cards.filter(\.isExpanded)
                    #expect(expandedCards.count == 1)
                    #expect(
                        expandedCards[0].taskIndex
                            == .some(StackDeckLayout.clampedExpandedIndex(expanded, taskCount: count))
                    )
                }
            }
        }
    }

    @Test("Past the first window the expanded task leads the next peeks")
    func shiftedWindow() {
        let indices = StackDeckLayout.visibleTaskIndices(taskCount: 12, expandedIndex: 6)
        #expect(indices == [6, 7, 8, 9, 10])
        let cards = StackDeckLayout.cards(taskCount: 12, expandedIndex: 6)
        guard case .overflow(let hidden, let first) = cards.last?.role else {
            Issue.record("Expected overflow")
            return
        }
        #expect(hidden == 1)
        #expect(first == 11)
    }

    @Test("Flipping clamps at the ends and does not reorder ids")
    func flipClampsWithoutReordering() {
        let ids = (0..<6).map { _ in UUID() }
        let original = ids
        #expect(StackDeckLayout.flippedIndex(current: 0, direction: -1, taskCount: 4) == 0)
        #expect(StackDeckLayout.flippedIndex(current: 3, direction: 1, taskCount: 4) == 3)
        #expect(StackDeckLayout.flippedIndex(current: 1, direction: 1, taskCount: 4) == 2)

        var expanded: UUID?
        var seen = [ids[0]]
        for _ in 0..<8 {
            expanded = StackDeckLayout.taskIDAfterFlip(from: expanded, ids: ids, direction: 1)
            let index = StackDeckLayout.expandedIndex(matching: expanded, in: ids)
            seen.append(ids[index])
        }
        #expect(ids == original)
        #expect(seen == [ids[0], ids[1], ids[2], ids[3], ids[4], ids[5], ids[5], ids[5], ids[5]])

        expanded = ids[2]
        expanded = StackDeckLayout.taskIDAfterFlip(from: expanded, ids: ids, direction: -1)
        #expect(expanded == ids[1])
        expanded = StackDeckLayout.taskIDAfterFlip(from: expanded, ids: ids, direction: -1)
        #expect(expanded == nil)
        #expect(StackDeckLayout.expandedIndex(matching: nil, in: ids) == 0)
        expanded = StackDeckLayout.taskIDAfterFlip(from: nil, ids: ids, direction: -1)
        #expect(expanded == nil)
    }

    @Test("Expanding resolves to a task id without moving Now")
    func expandIdentity() {
        let ids = (0..<4).map { _ in UUID() }
        #expect(StackDeckLayout.taskIDAfterExpand(index: 0, ids: ids) == nil)
        #expect(StackDeckLayout.taskIDAfterExpand(index: 2, ids: ids) == ids[2])
        #expect(StackDeckLayout.taskIDAfterExpand(index: 99, ids: ids) == ids[3])
        #expect(StackDeckLayout.expandedIndex(matching: UUID(), in: ids) == 0)
        #expect(StackDeckLayout.cards(taskCount: 0, expandedIndex: 3).isEmpty)
        let single = StackDeckLayout.cards(taskCount: 1, expandedIndex: 4)
        #expect(single.count == 1)
        #expect(single[0].isExpanded)
        #expect(single[0].taskIndex == .some(0))
    }

    @Test("Back cards keep a full-card body and only a peek between tops")
    func walletCardOffsets() {
        let full = 300.0
        let peek = 72.0
        #expect(StackDeckLayout.cardTopOffset(slot: 0, expandedSlot: 0, fullHeight: full, peekHeight: peek) == 0)
        #expect(StackDeckLayout.cardTopOffset(slot: 1, expandedSlot: 0, fullHeight: full, peekHeight: peek) == full)
        #expect(StackDeckLayout.cardTopOffset(slot: 2, expandedSlot: 0, fullHeight: full, peekHeight: peek) == full + peek)
        #expect(StackDeckLayout.cardTopOffset(slot: 4, expandedSlot: 0, fullHeight: full, peekHeight: peek) == full + peek * 3)
        #expect(StackDeckLayout.visibleStackHeight(visibleCount: 5, fullHeight: full, peekHeight: peek) == full + peek * 4)
        #expect(StackDeckLayout.visibleStackHeight(visibleCount: 0, fullHeight: full, peekHeight: peek) == 0)

        let above = StackDeckLayout.cardTopOffset(slot: 1, expandedSlot: 2, fullHeight: full, peekHeight: peek)
        let expanded = StackDeckLayout.cardTopOffset(slot: 2, expandedSlot: 2, fullHeight: full, peekHeight: peek)
        let below = StackDeckLayout.cardTopOffset(slot: 3, expandedSlot: 2, fullHeight: full, peekHeight: peek)
        #expect(above == peek)
        #expect(expanded - above == peek)
        #expect(below - expanded == full)
        // The card behind is full height, so it continues under the next card.
        #expect((above + full) - expanded == full - peek)

        let lastTop = StackDeckLayout.cardTopOffset(slot: 4, expandedSlot: 0, fullHeight: full, peekHeight: peek)
        let stackHeight = StackDeckLayout.visibleStackHeight(visibleCount: 5, fullHeight: full, peekHeight: peek)
        #expect(stackHeight - lastTop == peek)
        #expect(lastTop + full > stackHeight)
        #expect(StackDeckLayout.visibleStackHeight(visibleCount: 1, fullHeight: full, peekHeight: peek) == full)
        #expect(StackDeckLayout.cardTopOffset(slot: 1, expandedSlot: 0, fullHeight: .nan, peekHeight: peek) == 0)

        let mid = StackDeckLayout.cardTopOffset(slot: 1, expandedSlot: 0.5, fullHeight: full, peekHeight: peek)
        let atRest = StackDeckLayout.cardTopOffset(slot: 1, expandedSlot: 0, fullHeight: full, peekHeight: peek)
        let afterStep = StackDeckLayout.cardTopOffset(slot: 1, expandedSlot: 1, fullHeight: full, peekHeight: peek)
        #expect(abs(mid - ((atRest + afterStep) / 2)) < 0.001)
        #expect(
            StackDeckLayout.cardTopOffset(slot: 2, expandedSlot: 1.0, fullHeight: full, peekHeight: peek)
                == StackDeckLayout.cardTopOffset(slot: 2, expandedSlot: 1, fullHeight: full, peekHeight: peek)
        )
        #expect(StackDeckLayout.cardTopOffset(slot: 2, expandedSlot: .infinity, fullHeight: full, peekHeight: peek) == full + peek)
    }

    @Test("Depth scale compounds by 0.97 and peeks track Dynamic Type")
    func depthAndPeekScale() {
        #expect(StackDeckLayout.depthScale(depth: 0) == 1)
        #expect(StackDeckLayout.depthScale(depth: -3) == 1)
        #expect(abs(StackDeckLayout.depthScale(depth: 1) - 0.97) < 0.000_001)
        #expect(abs(StackDeckLayout.depthScale(depth: 2) - (0.97 * 0.97)) < 0.000_001)
        #expect(StackDeckLayout.scaledPeekHeight(factor: 1) == 72)
        #expect(StackDeckLayout.scaledPeekHeight(factor: 1.5) == 108)
        #expect(StackDeckLayout.scaledPeekHeight(factor: 0) == 72)
        #expect(StackDeckLayout.scaledPeekHeight(factor: .nan) == 72)
        #expect(StackDeckLayout.peekOverlap < StackDeckLayout.basePeekHeight / 2)
    }

    @Test("Running focus dims cards behind Now and restores them when it stops")
    func backdropDim() {
        #expect(StackDeckLayout.cardOpacity(isNowCard: true, focusIsRunning: true) == 1)
        #expect(
            StackDeckLayout.cardOpacity(isNowCard: false, focusIsRunning: true)
                == StackDeckLayout.runningBackdropOpacity
        )
        #expect(StackDeckLayout.cardOpacity(isNowCard: false, focusIsRunning: false) == 1)
        #expect(StackDeckLayout.cardOpacity(isNowCard: true, focusIsRunning: false) == 1)
        let contrasted = StackDeckLayout.cardOpacity(
            isNowCard: false,
            focusIsRunning: true,
            increaseContrast: true
        )
        #expect(contrasted == StackDeckLayout.runningBackdropOpacityIncreaseContrast)
        #expect(contrasted > StackDeckLayout.runningBackdropOpacity)
    }

    @Test("Reduced motion and reduced intensity crossfade instead of springing")
    func motionChoice() {
        #expect(StackDeckLayout.motion(reduceMotion: true, allowsMotion: true) == .crossfade)
        #expect(StackDeckLayout.motion(reduceMotion: false, allowsMotion: false) == .crossfade)
        #expect(StackDeckLayout.motion(reduceMotion: true, allowsMotion: false) == .crossfade)
        #expect(StackDeckLayout.motion(reduceMotion: false, allowsMotion: true) == .spring)
    }

    @Test("Shadows belong to light mode; deeper cards get a lighter tint")
    func depthStyle() {
        #expect(StackDeckLayout.showsDepthShadow(isDark: false))
        #expect(StackDeckLayout.showsDepthShadow(isDark: true) == false)
        #expect(StackDeckLayout.depthLightenAmount(depth: 0) == 0)
        #expect(StackDeckLayout.depthLightenAmount(depth: -2) == 0)
        #expect(StackDeckLayout.depthLightenAmount(depth: 2) > StackDeckLayout.depthLightenAmount(depth: 1))
        #expect(StackDeckLayout.depthLightenAmount(depth: 8) <= 0.18)
    }

    @Test("Swipe direction flips the deck")
    func swipeDirection() {
        #expect(StackDeckLayout.flipDirection(translation: -80) == 1)
        #expect(StackDeckLayout.flipDirection(translation: 80) == -1)
        #expect(StackDeckLayout.flipDirection(translation: 12) == 0)
        #expect(StackDeckLayout.flipDirection(translation: -10, predicted: -90) == 1)
        #expect(StackDeckLayout.flipDirection(translation: 70, predicted: 10) == -1)
    }

    @Test("VoiceOver label names the queue position")
    func voiceOverLabel() {
        #expect(
            StackDeckLayout.accessibilityLabel(
                position: 2,
                total: 5,
                title: "Write spec",
                detail: "20 min · Medium"
            ) == "Task 2 of 5, Write spec, 20 min · Medium"
        )
    }
}
