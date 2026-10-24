import SwiftUI

/// Stable identifiers for the critical UI smoke tests.
/// Query these instead of labels, colours, or layout.
enum QueueAccessibilityID {
    static let onboardingContinue = "onboarding.continue"
    static let onboardingTaskTitle = "onboarding.taskTitle"
    static let queueHome = "queue.home"
    static let queueAdd = "queue.add"
    static let taskTitle = "task.title"
    static let taskSave = "task.save"
    static let queueOpenFocus = "queue.openFocus"
    static let focusPause = "focus.pause"
    static let focusComplete = "focus.complete"
    static let celebrationXP = "celebration.xp"
}

/// Launch arguments the UI smoke tests pass. Absent for every normal launch.
enum QueueUITestLaunch {
    static let resetStore = "-queueUITestResetStore"
    static let skipOnboarding = "-queueUITestSkipOnboarding"

    static var isActive: Bool {
        resetsStore || skipsOnboarding
    }

    static var resetsStore: Bool {
        ProcessInfo.processInfo.arguments.contains(resetStore)
    }

    static var skipsOnboarding: Bool {
        ProcessInfo.processInfo.arguments.contains(skipOnboarding)
    }

    /// The focus smoke test must not raise the system notification prompt.
    static var skipsNotificationPrompt: Bool {
        skipsOnboarding
    }
}

extension View {
    @ViewBuilder
    func queueAccessibilityIdentifier(_ identifier: String?) -> some View {
        if let identifier {
            accessibilityIdentifier(identifier)
        } else {
            self
        }
    }
}
