import Foundation
import Testing
@testable import QueueCore

@Suite("Stack deck layout")
struct StackDeckLayoutTests {
    @Test("Now is always the top zIndex and zIndex falls as the index rises")
    func nowStaysInFront() {
        for count in 0...12 {
            for focus in [false, true] {
                for plain in [false, true] {
                    let cards = StackDeckLayout.cards(
                        taskCount: count,
                        nowHeight: 232,
                        focusIsRunning: focus,
                        plainList: plain
                    )
                    if count == 0 {
                        #expect(cards.isEmpty)
                        continue
                    }
                    let now = cards.first { $0.isNow }
                    #expect(now != nil)
                    let top = cards.map(\.zIndex).max()
                    #expect(now?.zIndex == top)
                    let others = cards.filter { !$0.isNow }
                    #expect(others.allSatisfy { now!.zIndex > $0.zIndex })
                    let layers = cards.map(\.zIndex)
                    #expect(layers == layers.sorted(by: >))
                    #expect(Set(layers).count == layers.count)
                }
            }
        }
    }

    @Test("At most four task cards show, and focus keeps only two behind Now")
    func visibleWindow() {
        for count in 0...12 {
            let idle = StackDeckLayout.cards(taskCount: count, focusIsRunning: false)
            let running = StackDeckLayout.cards(taskCount: count, focusIsRunning: true)
            #expect(taskCards(idle).count <= StackDeckLayout.maxVisibleTasks)
            #expect(behind(idle) <= StackDeckLayout.maxBehindCards)
            #expect(behind(running) <= StackDeckLayout.focusingBehindCards)
            #expect(taskCards(running).count <= 1 + StackDeckLayout.focusingBehindCards)
        }

        let five = StackDeckLayout.cards(taskCount: 5, nowHeight: 232, focusIsRunning: false)
        #expect(taskCards(five).map(\.taskIndex) == [0, 1, 2, 3])
        #expect(five.last?.footer?.hiddenCount == 1)
        #expect(five.last?.footer?.nextIndex == 4)

        let focusing = StackDeckLayout.cards(taskCount: 5, nowHeight: 232, focusIsRunning: true)
        #expect(taskCards(focusing).map(\.taskIndex) == [0, 1, 2])
        #expect(behind(focusing) == 2)
        #expect(focusing.last?.footer?.hiddenCount == 2)
        #expect(focusing.last?.footer?.nextIndex == 3)

        let exact = StackDeckLayout.cards(taskCount: 4, focusIsRunning: false)
        #expect(exact.allSatisfy { $0.footer == nil })
        #expect(taskCards(exact).count == 4)
    }

    @Test("Footer count plus visible cards equals the full queue")
    func footerAccountsForEveryone() {
        for count in 0...12 {
            for focus in [false, true] {
                let cards = StackDeckLayout.cards(taskCount: count, focusIsRunning: focus)
                let visible = taskCards(cards).count
                let footers = cards.compactMap(\.footer)
                #expect(footers.count <= 1)
                let hidden = footers.first?.hiddenCount ?? 0
                #expect(visible + hidden == count)
                if let footer = footers.first {
                    #expect(footer.nextIndex == visible)
                    #expect(hidden > 0)
                }
            }
        }
    }

    @Test("Stack order is the list order, and the widget uses that same order")
    func orderMatchesListAndWidget() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let tasks = [
            sample("To3", position: 2, at: 40),
            sample("Done", position: 5, at: 5, status: .completed),
            sample("Yo2", position: 1, at: 30),
            sample("Later tie", position: 3, at: 70),
            sample("Earlier tie", position: 3, at: 60),
            sample("Yo", position: 0, at: 20),
            sample("Pep3", position: 4, at: 80),
            sample("Skipped", position: 6, at: 90, status: .skipped)
        ]
        let listed = QueueOrdering.activeTasks(tasks)
        #expect(listed.map(\.title) == ["Yo", "Yo2", "To3", "Earlier tie", "Later tie", "Pep3"])

        let snapshot = QueueWidgetSnapshotBuilder.make(tasks: tasks, at: now)
        let widgetIDs = [snapshot.now?.id].compactMap { $0 } + snapshot.upNext.map(\.id)
        #expect(widgetIDs == listed.prefix(widgetIDs.count).map(\.id))
        #expect(snapshot.now?.title == "Yo")
        #expect(snapshot.upNext.first?.title == "Yo2")

        let cards = StackDeckLayout.cards(taskCount: listed.count, nowHeight: 232)
        let stackIDs = cards.compactMap(\.taskIndex).map { listed[$0].id }
        #expect(stackIDs == listed.prefix(stackIDs.count).map(\.id))
        #expect(cards.compactMap(\.taskIndex) == Array(0..<stackIDs.count))
        #expect(cards.last?.footer?.nextIndex == stackIDs.count)
        #expect(listed[cards.last?.footer?.nextIndex ?? 0].title == "Later tie")
    }

    @Test("Back cards tuck under the card above and the footer finishes the stack")
    func tuckAndBottomEdge() {
        let nowHeight = 232.0
        let cards = StackDeckLayout.cards(taskCount: 5, nowHeight: nowHeight, focusIsRunning: false)
        #expect(cards[0].y == 0)
        #expect(cards[0].height == nowHeight)
        #expect(cards[0].inset == 0)
        #expect(cards[1].inset == StackDeckLayout.insetStep)
        #expect(cards[2].inset == StackDeckLayout.insetStep * 2)
        #expect(cards[3].inset == StackDeckLayout.insetStep * 3)

        for index in 1..<4 {
            let previous = cards[index - 1]
            let card = cards[index]
            let previousBottom = previous.y + previous.height
            #expect(card.y < previousBottom)
            #expect(abs((previousBottom - card.y) - StackDeckLayout.tuck) < 0.001)
            #expect(abs((card.y + card.height - previousBottom) - StackDeckLayout.peekHeight) < 0.001)
        }

        let lastPeekBottom = cards[3].y + cards[3].height
        let footer = cards[4]
        #expect(footer.footer != nil)
        #expect(footer.y == lastPeekBottom)
        let height = StackDeckLayout.stackHeight(of: cards)
        #expect(footer.y + footer.height == height)
        for card in cards {
            #expect(card.y >= 0)
            #expect(card.y + card.height <= height + 0.001)
        }
    }

    @Test("Each step back is darker, and focus darkens the cards behind Now further")
    func darkerNotLighter() {
        #expect(StackDeckLayout.dimStep > 0)
        #expect(StackDeckLayout.focusDimBoost > 0)
        #expect(StackDeckLayout.dim(depth: 0, focusIsRunning: true) == 0)
        #expect(StackDeckLayout.dim(depth: 0, focusIsRunning: false) == 0)
        #expect(
            StackDeckLayout.dim(depth: 2, focusIsRunning: false)
                > StackDeckLayout.dim(depth: 1, focusIsRunning: false)
        )
        #expect(
            StackDeckLayout.dim(depth: 1, focusIsRunning: true)
                > StackDeckLayout.dim(depth: 1, focusIsRunning: false)
        )

        let idle = StackDeckLayout.cards(taskCount: 4, nowHeight: 232, focusIsRunning: false)
        let running = StackDeckLayout.cards(taskCount: 4, nowHeight: 232, focusIsRunning: true)
        #expect(abs(idle[1].dim - 0.06) < 0.000_001)
        #expect(abs(idle[2].dim - 0.12) < 0.000_001)
        #expect(abs(idle[3].dim - 0.18) < 0.000_001)
        #expect(running[0].dim == 0)
        #expect(running[1].dim > idle[1].dim)
        #expect(running[2].dim > running[1].dim)
        #expect(idle.last?.footer == nil)
    }

    @Test("Accessibility sizes lay the queue out as a plain list with no overlap")
    func plainListDoesNotOverlap() {
        let cards = StackDeckLayout.cards(
            taskCount: 6,
            nowHeight: 240,
            focusIsRunning: true,
            plainList: true
        )
        #expect(cards.compactMap(\.taskIndex) == Array(0..<6))
        #expect(cards.allSatisfy { $0.footer == nil })
        #expect(cards.allSatisfy { $0.inset == 0 })
        #expect(cards.allSatisfy { $0.dim == 0 })
        for index in cards.indices.dropFirst() {
            let previous = cards[index - 1]
            #expect(cards[index].y >= previous.y + previous.height)
            #expect(abs(cards[index].y - (previous.y + previous.height + StackDeckLayout.plainSpacing)) < 0.001)
        }
        let height = StackDeckLayout.stackHeight(of: cards)
        #expect(cards.last!.y + cards.last!.height <= height)
    }

    @Test("A bad Now height falls back, and an empty queue draws nothing")
    func sanitizesInput() {
        #expect(StackDeckLayout.cards(taskCount: 0, nowHeight: 232).isEmpty)
        let fallback = StackDeckLayout.cards(taskCount: 1, nowHeight: .nan)
        #expect(fallback.count == 1)
        #expect(fallback[0].height == StackDeckLayout.nowCardHeight)
        #expect(fallback[0].isNow)
        let negative = StackDeckLayout.cards(taskCount: 2, nowHeight: -10, focusIsRunning: true)
        #expect(negative[0].height == StackDeckLayout.nowCardHeight)
        #expect(behind(negative) == 1)
        #expect(negative.allSatisfy { $0.footer == nil })
    }

    @Test("Footer copy names the hidden count and the next title")
    func footerCopy() {
        #expect(
            StackDeckLayout.footerTitle(hiddenCount: 1, nextTitle: "Update LinkedIn headline")
                == "+1 more · Update LinkedIn headline"
        )
        #expect(
            StackDeckLayout.footerAccessibilityLabel(hiddenCount: 1, nextTitle: "Update LinkedIn headline")
                == "1 more task, Update LinkedIn headline"
        )
        #expect(
            StackDeckLayout.footerAccessibilityLabel(hiddenCount: 2, nextTitle: "To3")
                == "2 more tasks, To3"
        )
    }

    @Test("VoiceOver names the queue position")
    func voiceOverLabel() {
        #expect(
            StackDeckLayout.accessibilityLabel(
                position: 2,
                total: 5,
                title: "Yo2",
                detail: "15 min · Medium"
            ) == "Task 2 of 5, Yo2, 15 min · Medium"
        )
    }

    @Test("The deck springs unless motion is reduced")
    func motionChoice() {
        #expect(StackDeckLayout.springDuration == 0.35)
        #expect(StackDeckLayout.motion(reduceMotion: false, allowsMotion: true) == .spring)
        #expect(StackDeckLayout.motion(reduceMotion: true, allowsMotion: true) == .crossfade)
        #expect(StackDeckLayout.motion(reduceMotion: false, allowsMotion: false) == .crossfade)
        #expect(StackDeckLayout.peekHeight == 58)
        #expect(StackDeckLayout.insetStep == 4)
        #expect(StackDeckLayout.maxVisibleTasks == 4)
        #expect(StackDeckLayout.focusingBehindCards == 2)
    }

    private func taskCards(_ cards: [StackDeckLayout.Card]) -> [StackDeckLayout.Card] {
        cards.filter { $0.taskIndex != nil }
    }

    private func behind(_ cards: [StackDeckLayout.Card]) -> Int {
        cards.compactMap(\.taskIndex).filter { $0 > 0 }.count
    }

    private func sample(
        _ title: String,
        position: Int,
        at offset: TimeInterval,
        status: TaskStatus = .queued
    ) -> QueueTask {
        QueueTask(
            title: title,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000 + offset),
            queuePosition: position,
            status: status
        )
    }
}
