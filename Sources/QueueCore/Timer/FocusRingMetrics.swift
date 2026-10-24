import Foundation

/// Shared focus-ring rules for the session screen, Lock Screen, and Live Activity.
/// Honey is a dark-mode time's-up stroke only. Light mode never uses it on a bare ring.
public enum FocusRingMetrics {
    /// Immersive focus ring. Smaller surfaces keep their own width.
    public static let focusLineWidth: Double = 10
    /// Diameter of the immersive focus ring, in points.
    public static let focusDiameter: Double = 220
    /// Dim track behind the progress stroke.
    public static let trackOpacity: Double = 0.15
    /// Caption inside the ring stays within this fraction of the diameter.
    public static let captionWidthFraction: Double = 0.70
    /// One half of the single time's-up breath. Slow, so it does not read as an alarm.
    public static let timeUpPulseDuration: TimeInterval = 1.35

    public enum Stroke: Equatable, Sendable {
        /// Theme primary. Running rings, and the light-mode time's-up ring.
        case primary
        /// Honey. Dark-mode time's-up ring only.
        case accent
        /// Muted. Pause is announced in words; the stroke is secondary text.
        case paused
    }

    /// Clamped remaining fraction. Time's up draws a full ring instead of an empty one.
    public static func ringFill(progress: Double, isTimeUp: Bool) -> Double {
        if isTimeUp { return 1 }
        guard progress.isFinite else { return 0 }
        return min(1, max(0, progress))
    }

    /// Remaining time over the planned length. Shrinks as the session runs down.
    /// A non-positive plan is an empty ring, unless time is up, which is always full.
    public static func ringFill(remaining: TimeInterval, planned: TimeInterval, isTimeUp: Bool) -> Double {
        let progress: Double
        if planned > 0, remaining.isFinite, planned.isFinite {
            progress = remaining / planned
        } else {
            progress = 0
        }
        return ringFill(progress: progress, isTimeUp: isTimeUp)
    }

    /// Time's up wins over pause. Light mode never returns honey. Danger is not a ring colour.
    public static func stroke(isTimeUp: Bool, isPaused: Bool, isDark: Bool) -> Stroke {
        if isTimeUp {
            return isDark ? .accent : .primary
        }
        if isPaused {
            return .paused
        }
        return .primary
    }

    public static func strokeRole(isTimeUp: Bool, isPaused: Bool, isDark: Bool) -> QueuePaletteRole {
        switch stroke(isTimeUp: isTimeUp, isPaused: isPaused, isDark: isDark) {
        case .primary:
            return .primary
        case .accent:
            return .accent
        case .paused:
            return .textSecondary
        }
    }
}
