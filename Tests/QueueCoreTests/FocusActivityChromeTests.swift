import Foundation
import Testing
@testable import QueueCore

@Suite("Focus Live Activity chrome")
struct FocusActivityChromeTests {
    @Test("Running copy names the difficulty, and paused is a word")
    func runningAndPaused() {
        #expect(FocusActivityChrome.statusCaption(
            state: .running,
            difficultyDisplayName: "Medium",
            remaining: 13 * 60 + 41,
            isStale: false
        ) == "Medium · focusing")
        #expect(FocusActivityChrome.isTimeUp(state: .running, remaining: 13 * 60 + 41, isStale: false) == false)

        #expect(FocusActivityChrome.statusCaption(
            state: .paused,
            difficultyDisplayName: "Medium",
            remaining: 8 * 60,
            isStale: false
        ) == "Paused")
        #expect(FocusActivityChrome.isTimeUp(state: .paused, remaining: 0, isStale: true) == false)
    }

    @Test("Time's up is text when the session expires, hits zero, or goes stale")
    func timesUp() {
        let expected = "Time\u{2019}s up"
        #expect(FocusActivityChrome.statusCaption(
            state: .expired,
            difficultyDisplayName: "Medium",
            remaining: 0,
            isStale: false
        ) == expected)
        #expect(FocusActivityChrome.statusCaption(
            state: .running,
            difficultyDisplayName: "Medium",
            remaining: 0,
            isStale: false
        ) == expected)
        #expect(FocusActivityChrome.statusCaption(
            state: .running,
            difficultyDisplayName: "Medium",
            remaining: 5,
            isStale: true
        ) == expected)
        #expect(FocusActivityChrome.isTimeUp(state: .expired, remaining: 30, isStale: false))
        #expect(FocusActivityChrome.isTimeUp(state: .running, remaining: 0, isStale: false))
        #expect(FocusActivityChrome.isTimeUp(state: .running, remaining: 5, isStale: true))
    }

    @Test("Honey is only the completed ring in dark mode")
    func ringUsesHoneyOnlyWhenDarkAndComplete() {
        #expect(FocusActivityChrome.ringUsesHoney(isComplete: true, isDark: true))
        #expect(FocusActivityChrome.ringUsesHoney(isComplete: true, isDark: false) == false)
        #expect(FocusActivityChrome.ringUsesHoney(isComplete: false, isDark: true) == false)
        #expect(FocusActivityChrome.ringUsesHoney(isComplete: false, isDark: false) == false)
    }
}
