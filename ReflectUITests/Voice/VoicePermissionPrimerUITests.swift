import XCTest

/// Drives the voice recorder's inline permission primer, opened through the `reflect://voice`
/// widget link from the seeded chapter.
///
/// The simulator can reset the microphone but not speech recognition, so the statuses the recorder
/// reads come from `-uiTestingVoicePermission notDetermined|granted` (see `VoicePermission`). The
/// system prompts behind "Continue" are real: the microphone is reset before that launch.
///
/// Every state saves a screenshot (kept even on success) for the UI check on the issue.
@MainActor
final class VoicePermissionPrimerUITests: XCTestCase {
    /// The Learning the `-uiTesting` hook seeds (see `ReflectApp.seedForUITestingIfNeeded`).
    private let seededLearningID = "00000000-0000-0000-0000-000000000001"
    private let primerID = "voice.permissionPrimer"
    private let timeout: TimeInterval = 10
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testPrimerShowsInlineInTheRecorderWhenNotDetermined() throws {
        let app = launch(permission: "notDetermined")
        try openVoiceRecorder(in: app)

        let primer = element(primerID, in: app)
        XCTAssertTrue(primer.waitForExistence(timeout: timeout), "No primer while access is not determined")
        XCTAssertTrue(element("voice.permissionPrimer.continue", in: app).exists, "No Continue button")
        // Inline, not a cover: the recorder's title and record button are still on screen.
        XCTAssertTrue(app.navigationBars["Voice Note"].exists, "The recorder is covered")
        XCTAssertTrue(element("voice.record", in: app).exists, "The record button is gone")
        XCTAssertFalse(app.staticTexts["Tap to start recording"].exists, "Primer and idle hint both show")
        XCTAssertFalse(springboard.alerts.firstMatch.exists, "System prompt fired before Continue")
        attachScreenshot("1-recorder-with-primer", of: app)
    }

    func testNoPrimerWhenBothGranted() throws {
        let app = launch(permission: "granted")
        try openVoiceRecorder(in: app)

        XCTAssertTrue(app.staticTexts["Tap to start recording"].waitForExistence(timeout: timeout))
        XCTAssertFalse(element(primerID, in: app).exists, "Primer shows with both permissions granted")
        XCTAssertTrue(element("voice.record", in: app).exists, "No record button")
        attachScreenshot("2-recorder-without-primer", of: app)
    }

    func testContinueGoesStraightToTheMicrophonePrompt() throws {
        let app = launch(permission: "notDetermined", resettingMicrophone: true)
        try openVoiceRecorder(in: app)

        let continueButton = element("voice.permissionPrimer.continue", in: app)
        XCTAssertTrue(continueButton.waitForExistence(timeout: timeout), "No Continue button")
        continueButton.tap()

        let microphonePrompt = springboard.alerts.firstMatch
        XCTAssertTrue(microphonePrompt.waitForExistence(timeout: timeout), "Continue did not ask for the microphone")
        XCTAssertTrue(microphonePrompt.label.localizedCaseInsensitiveContains("microphone"), "First prompt: \(microphonePrompt.label)")
        attachScreenshot("3-microphone-prompt", of: app)
        microphonePrompt.buttons["Allow"].tap()

        // Speech is asked right after, unless an earlier run on this simulator already answered it.
        let speechPrompt = springboard.alerts.firstMatch
        if speechPrompt.waitForExistence(timeout: 3) {
            XCTAssertTrue(speechPrompt.label.localizedCaseInsensitiveContains("speech"), "Second prompt: \(speechPrompt.label)")
            attachScreenshot("4-speech-prompt", of: app)
            speechPrompt.buttons.matching(NSPredicate(format: "label IN %@", ["OK", "Allow"])).firstMatch.tap()
        }

        XCTAssertTrue(springboard.alerts.firstMatch.waitForNonExistence(timeout: timeout))
        XCTAssertTrue(element("voice.recorder", in: app).exists, "The recorder closed after the prompts")
    }

    // MARK: - Flow

    private func launch(permission: String, resettingMicrophone: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        if resettingMicrophone {
            app.resetAuthorizationStatus(for: .microphone)
        }
        app.launchArguments = [
            "-uiTesting",
            "-uiTestingVoicePermission", permission,
            // Argument-domain overrides, so a previous run on this simulator can't change the start state.
            "-hasCompletedOnboarding", "YES",
            "-debugAlwaysShowOnboarding", "NO",
            "-lastOpenedLearningId", seededLearningID,
        ]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: timeout))
        XCTAssertTrue(element("reflections.list", in: app).waitForExistence(timeout: timeout))
        return app
    }

    private func openVoiceRecorder(in app: XCUIApplication) throws {
        app.open(try XCTUnwrap(URL(string: "reflect://voice")))
        XCTAssertTrue(element("voice.recorder", in: app).waitForExistence(timeout: timeout), "The recorder did not open")
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
