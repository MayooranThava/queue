import Testing
import Foundation
@testable import QueueCore

@Suite("SmartGapsEngine")
struct SmartGapsEngineTests {
    let now = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("Merges overlapping meetings and suggests FIFO fit")
    func suggestFIFO() {
        let engine = SmartGapsEngine(preparationBuffer: 5 * 60)
        let events = [
            CalendarEvent(
                id: "1",
                sourceProvider: "eventkit",
                calendarID: "c",
                start: now.addingTimeInterval(30 * 60),
                end: now.addingTimeInterval(60 * 60),
                title: "Standup"
            ),
            CalendarEvent(
                id: "2",
                sourceProvider: "eventkit",
                calendarID: "c",
                start: now.addingTimeInterval(50 * 60),
                end: now.addingTimeInterval(90 * 60),
                title: "Overlap"
            )
        ]
        let tasks = [
            QueueTask(title: "Emails", estimatedDuration: 10 * 60, queuePosition: 0),
            QueueTask(title: "Deep work", estimatedDuration: 45 * 60, queuePosition: 1)
        ]
        let suggestion = engine.suggest(tasks: tasks, events: events, from: now)
        #expect(suggestion?.taskTitle == "Emails")
        #expect(suggestion?.breaksFIFOOrder == false)
    }

    @Test("Recommends out-of-order with explanation when head does not fit")
    func outOfOrder() {
        let engine = SmartGapsEngine(preparationBuffer: 5 * 60)
        let events = [
            CalendarEvent(
                id: "1",
                sourceProvider: "eventkit",
                calendarID: "c",
                start: now.addingTimeInterval(22 * 60),
                end: now.addingTimeInterval(60 * 60),
                title: "Meeting"
            )
        ]
        let tasks = [
            QueueTask(title: "Prepare presentation", estimatedDuration: 45 * 60, queuePosition: 0),
            QueueTask(title: "Reply to emails", estimatedDuration: 10 * 60, queuePosition: 1)
        ]
        let suggestion = engine.suggest(tasks: tasks, events: events, from: now)
        #expect(suggestion?.taskTitle == "Reply to emails")
        #expect(suggestion?.breaksFIFOOrder == true)
        #expect(suggestion?.explanation.contains("Confirm") == true)
    }

    @Test("Ignores cancelled and all-day events")
    func ignoreNoise() {
        let engine = SmartGapsEngine(preparationBuffer: 0)
        let events = [
            CalendarEvent(
                id: "1",
                sourceProvider: "eventkit",
                calendarID: "c",
                start: now,
                end: now.addingTimeInterval(3600),
                isAllDay: true
            ),
            CalendarEvent(
                id: "2",
                sourceProvider: "eventkit",
                calendarID: "c",
                start: now.addingTimeInterval(600),
                end: now.addingTimeInterval(1200),
                isCancelled: true
            )
        ]
        let tasks = [QueueTask(title: "Tidy desk", estimatedDuration: 5 * 60)]
        let suggestion = engine.suggest(tasks: tasks, events: events, from: now, lookAhead: 3600)
        #expect(suggestion?.taskTitle == "Tidy desk")
    }
}
