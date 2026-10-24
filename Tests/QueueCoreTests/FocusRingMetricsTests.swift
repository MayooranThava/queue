import Foundation
import Testing
@testable import QueueCore

@Suite("Focus ring metrics")
struct FocusRingMetricsTests {
    @Test("The immersive ring is a 10pt stroke over a 15 percent track")
    func tokens() {
        #expect(FocusRingMetrics.focusLineWidth == 10)
        #expect(FocusRingMetrics.focusDiameter == 220)
        #expect(FocusRingMetrics.trackOpacity == 0.15)
        #expect(FocusRingMetrics.captionWidthFraction == 0.70)
        #expect(FocusRingMetrics.timeUpPulseDuration >= 1)
    }

    @Test("The ring shrinks with remaining time and clamps into 0...1")
    func shrinksAsTimeRunsDown() {
        let planned = 600.0
        let samples = [600.0, 450, 300, 150, 0].map {
            FocusRingMetrics.ringFill(remaining: $0, planned: planned, isTimeUp: false)
        }
        #expect(samples == [1, 0.75, 0.5, 0.25, 0])
        #expect(FocusRingMetrics.ringFill(remaining: 900, planned: planned, isTimeUp: false) == 1)
        #expect(FocusRingMetrics.ringFill(remaining: -20, planned: planned, isTimeUp: false) == 0)
        #expect(FocusRingMetrics.ringFill(remaining: 10, planned: 0, isTimeUp: false) == 0)
        #expect(FocusRingMetrics.ringFill(remaining: .nan, planned: planned, isTimeUp: false) == 0)
        #expect(FocusRingMetrics.ringFill(remaining: .infinity, planned: planned, isTimeUp: false) == 0)
        #expect(FocusRingMetrics.ringFill(progress: 1.4, isTimeUp: false) == 1)
        #expect(FocusRingMetrics.ringFill(progress: -0.2, isTimeUp: false) == 0)
        #expect(FocusRingMetrics.ringFill(progress: .nan, isTimeUp: false) == 0)
    }

    @Test("Time's up fills the ring even when remaining time is zero")
    func timeUpIsFull() {
        #expect(FocusRingMetrics.ringFill(remaining: 0, planned: 600, isTimeUp: true) == 1)
        #expect(FocusRingMetrics.ringFill(remaining: 30, planned: 600, isTimeUp: true) == 1)
        #expect(FocusRingMetrics.ringFill(remaining: 0, planned: 0, isTimeUp: true) == 1)
        #expect(FocusRingMetrics.ringFill(progress: 0, isTimeUp: true) == 1)
    }

    @Test("Honey is only the dark time's-up stroke; light mode stays on primary")
    func strokeFollowsSchemeAndState() {
        #expect(FocusRingMetrics.stroke(isTimeUp: true, isPaused: false, isDark: true) == .accent)
        #expect(FocusRingMetrics.stroke(isTimeUp: true, isPaused: true, isDark: true) == .accent)
        #expect(FocusRingMetrics.stroke(isTimeUp: true, isPaused: false, isDark: false) == .primary)
        #expect(FocusRingMetrics.stroke(isTimeUp: false, isPaused: false, isDark: true) == .primary)
        #expect(FocusRingMetrics.stroke(isTimeUp: false, isPaused: false, isDark: false) == .primary)
        #expect(FocusRingMetrics.stroke(isTimeUp: false, isPaused: true, isDark: true) == .paused)
        #expect(FocusRingMetrics.stroke(isTimeUp: false, isPaused: true, isDark: false) == .paused)

        for isTimeUp in [true, false] {
            for isPaused in [true, false] {
                for isDark in [true, false] {
                    let role = FocusRingMetrics.strokeRole(
                        isTimeUp: isTimeUp,
                        isPaused: isPaused,
                        isDark: isDark
                    )
                    #expect(role != .danger)
                    if !isDark {
                        #expect(role != .accent)
                    }
                }
            }
        }

        #expect(FocusRingMetrics.strokeRole(isTimeUp: true, isPaused: false, isDark: true) == .accent)
        #expect(FocusRingMetrics.strokeRole(isTimeUp: true, isPaused: false, isDark: false) == .primary)
        #expect(FocusRingMetrics.strokeRole(isTimeUp: false, isPaused: true, isDark: true) == .textSecondary)
    }

    @Test("Choosing primary in light mode is not the honey swatch")
    func lightPrimaryIsNotHoney() {
        for theme in QueueTheme.all {
            for increased in [false, true] {
                let primary = theme.resolved(.primary, dark: false, increasedContrast: increased)
                let honey = theme.resolved(.accent, dark: false, increasedContrast: increased)
                #expect(primary != honey)
            }
        }
    }
}
