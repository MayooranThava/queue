import Foundation

/// The one order the queue is shown in.
///
/// List, Stack, and the widget all call this. Nothing else sorts the active
/// queue for display. Position wins; an equal position falls back to creation
/// time so the order stays stable when two rows share a slot.
public enum QueueOrdering {
    public static func comesBefore(_ lhs: QueueTask, _ rhs: QueueTask) -> Bool {
        if lhs.queuePosition != rhs.queuePosition {
            return lhs.queuePosition < rhs.queuePosition
        }
        return lhs.createdAt < rhs.createdAt
    }

    public static func sorted(_ tasks: [QueueTask]) -> [QueueTask] {
        tasks.sorted(by: comesBefore)
    }

    /// Active tasks in the order List, Stack, and the widget show them.
    public static func activeTasks(_ tasks: [QueueTask]) -> [QueueTask] {
        sorted(tasks.filter(\.isInActiveQueue))
    }
}
