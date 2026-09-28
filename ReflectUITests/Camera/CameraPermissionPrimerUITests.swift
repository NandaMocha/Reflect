import XCTest

/// Drives the camera-reflection flow's permission primer, started through the `reflect://camera`
/// widget link from the seeded chapter.
///
/// Camera access is reset before each launch, so the flow starts from `notDetermined`. The
/// "Allow" path is not covered: the simulator has no camera, so it can't open one. That path is on
/// the device checklist.
///
/// Every state saves a screenshot (kept even on success) for the UI check on the issue.
@MainActor
final class CameraPermissionPrimerUITests: XCTestCase {
    /// The Learning the `-uiTesting` hook seeds (see `ReflectApp.seedForUITestingIfNeeded`).
    private let seededLearningID = "00000000-0000-0000-0000-000000000001"
    private let primerID = "camera.permissionPrimer"
    private let timeout: TimeInterval = 10
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testPrimerIsASmallSheetWithContinueAndNotNow() throws {
        let app = launchOnChapter()
        try openCameraLink(in: app)

        let primer = element(primerID, in: app)
        XCTAssertTrue(primer.waitForExistence(timeout: timeout), "Primer did not appear for an undetermined camera")
        XCTAssertTrue(app.staticTexts["Allow Camera Access"].exists)
        XCTAssertTrue(app.buttons["Continue"].exists)
        XCTAssertTrue(app.buttons["Not Now"].exists)
        // A detent sheet, not a full-screen cover: the chapter stays visible above it.
        XCTAssertLessThan(primer.frame.height, app.frame.height * 0.75, "Primer is not a small sheet")
        XCTAssertFalse(springboard.alerts.firstMatch.exists, "System prompt fired before Continue")
        attachScreenshot("1-primer-not-determined", of: app)
    }

    func testNotNowClosesWithoutAskingOrAlerting() throws {
        let app = launchOnChapter()
        try openCameraLink(in: app)
        XCTAssertTrue(element(primerID, in: app).waitForExistence(timeout: timeout))

        app.buttons["Not Now"].tap()

        XCTAssertTrue(element(primerID, in: app).waitForNonExistence(timeout: timeout), "Primer stayed after Not Now")
        XCTAssertFalse(springboard.alerts.firstMatch.waitForExistence(timeout: 2), "Not Now fired the system prompt")
        XCTAssertFalse(app.alerts["Camera Access Needed"].exists, "Not Now showed the Settings alert")
        XCTAssertTrue(element("reflections.list", in: app).exists, "Not Now left the chapter")
        attachScreenshot("2-not-now-closed", of: app)
    }

    func testContinueAsksThenDenyClosesAndNextTapShowsSettingsAlert() throws {
        let app = launchOnChapter()
        try openCameraLink(in: app)
        XCTAssertTrue(element(primerID, in: app).waitForExistence(timeout: timeout))

        app.buttons["Continue"].tap()

        let prompt = springboard.alerts.firstMatch
        XCTAssertTrue(prompt.waitForExistence(timeout: timeout), "Continue did not fire the system prompt")
        XCTAssertTrue(element(primerID, in: app).exists, "Primer left before the system prompt answered")
        attachScreenshot("3-system-prompt-over-primer", of: springboard)

        prompt.buttons["Don’t Allow"].firstMatch.tap()

        XCTAssertTrue(element(primerID, in: app).waitForNonExistence(timeout: timeout), "Primer stayed after Don't Allow")
        XCTAssertFalse(app.alerts["Camera Access Needed"].waitForExistence(timeout: 2), "Deny showed the Settings alert right away")
        XCTAssertTrue(element("reflections.list", in: app).exists, "Deny left the chapter")
        attachScreenshot("4-denied-closed-cleanly", of: app)

        // Denied now: the next start skips the primer and points to Settings.
        try openCameraLink(in: app)
        XCTAssertTrue(app.alerts["Camera Access Needed"].waitForExistence(timeout: timeout), "No Settings alert while denied")
        XCTAssertFalse(element(primerID, in: app).exists, "Primer shown again while denied")
        XCTAssertTrue(app.alerts.buttons["Open Settings"].exists)
        attachScreenshot("5-denied-settings-alert", of: app)
    }

    // MARK: - Helpers

    /// Starts inside the seeded chapter with camera access reset to not determined.
    private func launchOnChapter() -> XCUIApplication {
        let app = XCUIApplication()
        app.resetAuthorizationStatus(for: .camera)
        app.launchArguments = [
            "-uiTesting",
            // Argument-domain overrides, so a previous run on this simulator can't change the start state.
            "-hasCompletedOnboarding", "YES",
            "-debugAlwaysShowOnboarding", "NO",
            "-hasSeenVoiceIntro", "YES",
            "-lastOpenedLearningId", seededLearningID,
        ]
        app.launch()
        XCTAssertTrue(element("reflections.list", in: app).waitForExistence(timeout: timeout))
        return app
    }

    private func openCameraLink(in app: XCUIApplication) throws {
        app.open(try XCTUnwrap(URL(string: "reflect://camera")))
    }

    /// Keeps the screenshot even when the test passes, so the UI check can compare it with the Goal.
    private func attachScreenshot(_ name: String, of app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }
}
