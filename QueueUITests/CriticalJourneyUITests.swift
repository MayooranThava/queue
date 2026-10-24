import XCTest

/// Critical smoke flows. They look up accessibility identifiers only, so copy
/// and layout can change without a rewrite.
final class CriticalJourneyUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testOnboardingCompletes() {
        let app = XCUIApplication()
        app.launchArguments = [QueueUITestLaunch.resetStore]
        app.launch()

        let title = element(QueueAccessibilityID.onboardingTaskTitle, in: app)
        var taps = 0
        while !title.exists && taps < 8 {
            let advance = wait(QueueAccessibilityID.onboardingContinue, in: app)
            if !advance.isEnabled || !advance.isHittable {
                break
            }
            advance.tap()
            taps += 1
            _ = title.waitForExistence(timeout: 2)
        }
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        title.typeText("Outline the intro")
        dismissKeyboard(in: app)

        let start = wait(QueueAccessibilityID.onboardingContinue, in: app)
        if !start.isEnabled {
            title.tap()
            title.typeText("Outline the intro")
            dismissKeyboard(in: app)
        }
        start.tap()

        let home = element(QueueAccessibilityID.queueHome, in: app)
        XCTAssertTrue(home.waitForExistence(timeout: 20))
        XCTAssertFalse(element(QueueAccessibilityID.onboardingContinue, in: app).exists)
    }

    func testAddTaskStartFocusCompleteShowsXP() {
        let app = XCUIApplication()
        app.launchArguments = [QueueUITestLaunch.resetStore, QueueUITestLaunch.skipOnboarding]
        app.launch()

        wait(QueueAccessibilityID.queueAdd, in: app).tap()

        let title = wait(QueueAccessibilityID.taskTitle, in: app, timeout: 10)
        title.tap()
        title.typeText("Ship the notes")
        wait(QueueAccessibilityID.taskSave, in: app, timeout: 5).tap()

        wait(QueueAccessibilityID.queueOpenFocus, in: app, timeout: 15).tap()

        _ = wait(QueueAccessibilityID.focusPause, in: app)
        wait(QueueAccessibilityID.focusComplete, in: app, timeout: 5).tap()

        let xp = element(QueueAccessibilityID.celebrationXP, in: app)
        XCTAssertTrue(xp.waitForExistence(timeout: 15))
    }

    /// The first hittable match. The add button exists twice on an empty queue.
    private func wait(
        _ identifier: String,
        in app: XCUIApplication,
        timeout: TimeInterval = 20
    ) -> XCUIElement {
        let matches = app.descendants(matching: .any).matching(identifier: identifier)
        let probe = matches.firstMatch
        XCTAssertTrue(probe.waitForExistence(timeout: timeout), "Timed out waiting for \(identifier)")
        let limit = Date().addingTimeInterval(2)
        while Date() < limit {
            if let hittable = matches.allElementsBoundByIndex.first(where: { $0.isHittable }) {
                return hittable
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return probe
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func dismissKeyboard(in app: XCUIApplication) {
        let labels = ["Done", "done", "Return", "return"]
        for label in labels {
            let key = app.keyboards.buttons[label]
            if key.exists {
                key.tap()
                return
            }
        }
    }
}
