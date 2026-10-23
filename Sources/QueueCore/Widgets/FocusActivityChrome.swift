import Foundation

/// Copy and ring tone shared by the Lock Screen, Dynamic Island, and Watch presentations.
public enum FocusActivityChrome {
    /// Paused and time's up are words. Color is extra, not the only signal.
    public static func statusCaption(
        state: FocusTimerState,
        difficultyDisplayName: String,
        remaining: TimeInterval,
        isStale: Bool
    ) -> String {
        if isTimeUp(state: state, remaining: remaining, isStale: isStale) {
            return "Time\u{2019}s up"
        }
        if state == .paused {
            return "Paused"
        }
        return "\(difficultyDisplayName) · focusing"
    }

    /// Honey is a dark-mode completed ring only. Light mode strokes stay terracotta.
    public static func ringUsesHoney(isComplete: Bool, isDark: Bool) -> Bool {
        isDark && isComplete
    }

    public static func isTimeUp(
        state: FocusTimerState,
        remaining: TimeInterval,
        isStale: Bool
    ) -> Bool {
        switch state {
        case .paused:
            return false
        case .expired:
            return true
        case .running, .idle, .completed:
            return isStale || remaining <= 0
        }
    }

    /// "Next: <title>" when a following block exists. Blank titles are omitted.
    public static func nextLine(_ title: String?) -> String? {
        guard let title else { return nil }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return "Next: \(trimmed)"
    }
}
