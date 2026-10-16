import Foundation

/// Projects wall-clock start times for an ordered active queue.
/// Head starts at `now` (or its planned start if still ahead); each following
/// task starts after the previous estimate, unless it has an explicit planned start.
public enum QueueSchedule {
    public static func projectedStarts(
        orderedActiveTasks: [QueueTask],
        from now: Date
    ) -> [UUID: Date] {
        var result: [UUID: Date] = [:]
        var cursor = now

        for task in orderedActiveTasks {
            let start: Date
            if let planned = task.plannedStartAt, planned > cursor {
                start = planned
            } else if let planned = task.plannedStartAt, planned <= cursor, task.status == .queued {
                // Missed optional plan — show “now” / next free slot rather than a past time.
                start = cursor
            } else {
                start = cursor
            }
            result[task.id] = start
            cursor = start.addingTimeInterval(max(60, task.estimatedDuration))
        }
        return result
    }
}
