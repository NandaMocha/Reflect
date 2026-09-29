import XCTest

/// Records a voice note from the reflection editor and checks what the transcript area shows
/// once the recording stops.
///
/// The simulator's speech recognizer can't be steered, so `-uiTestingSpeech <scenario>` swaps in
/// `UITestingSpeechRecognitionService` (DEBUG only). The audio itself is recorded for real, which
/// is why the microphone prompt is answered on first use.
///
/// Every transcript state saves a screenshot (kept even on success) for the UI check on the issue.
@MainActor
final class VoiceNoteUITests: XCTestCase {
    /// The Learning the `-uiTesting` hook seeds (see `ReflectApp.seedForUITestingIfNeeded`).
    private let seededLearningID = "00000000-0000-0000-0000-000000000001"
    private let timeout: TimeInterval = 10
    /// Must match `UITestingSpeechRecognitionService.transcript`.
    private let fakeTranscript = "Today I learned that the voice note keeps its audio even when the transcript fails."

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Transcript states

    func testLiveTranscriptIsShown() throws {
        let app = try recordAndStop(scenario: "live")

        let card = element("voice.transcript.text", in: app)
        XCTAssertTrue(card.waitForExistence(timeout: timeout), "The live transcript did not show")
        XCTAssertTrue(app.staticTexts[fakeTranscript].exists, "The transcript card does not hold the live text")
        attachScreenshot("transcript-live", of: app)
    }

    func testFallbackTranscriptIsShownWhenLiveFails() throws {
        let app = try recordAndStop(scenario: "fallback")

        let card = element("voice.transcript.text", in: app)
        XCTAssertTrue(card.waitForExistence(timeout: timeout), "The fallback transcript did not show")
        XCTAssertTrue(app.staticTexts[fakeTranscript].exists, "The transcript card does not hold the fallback text")
        attachScreenshot("transcript-fallback", of: app)
    }

    func testNoSpeechStatusIsShown() throws {
        let app = try recordAndStop(scenario: "noSpeech")

        XCTAssertTrue(element("voice.transcript.noSpeech", in: app).waitForExistence(timeout: timeout))
        XCTAssertFalse(element("voice.transcript.text", in: app).exists)
        attachScreenshot("no-speech", of: app)
    }

    func testUnavailableStatusIsShown() throws {
        let app = try recordAndStop(scenario: "unavailable")

        XCTAssertTrue(element("voice.transcript.unavailable", in: app).waitForExistence(timeout: timeout))
        XCTAssertFalse(element("voice.transcript.text", in: app).exists)
        attachScreenshot("unavailable", of: app)
    }

    /// The fallback never answers here, so this also checks that Done does not wait for it.
    func testTranscribingStatusIsShownAndDoneSavesWithoutWaiting() throws {
        let app = try recordAndStop(scenario: "transcribing")

        XCTAssertTrue(element("voice.transcript.transcribing", in: app).waitForExistence(timeout: timeout))
        // Playback is there while transcribing: the play control and Done are on screen.
        XCTAssertTrue(app.navigationBars.buttons["Done"].exists, "Done is missing while transcribing")
        attachScreenshot("transcribing", of: app)

        app.navigationBars.buttons["Done"].tap()

        XCTAssertTrue(
            element("voice.recorder", in: app).waitForNonExistence(timeout: 3),
            "Done waited for the transcript instead of saving"
        )
        XCTAssertTrue(
            app.staticTexts["Voice Note"].waitForExistence(timeout: timeout),
            "The recording was not added to the reflection"
        )
        attachScreenshot("transcribing-done-saved", of: app)
    }

    // MARK: - Helpers

    /// Opens the reflection editor, records about a second of audio and stops, leaving the
    /// recorder on its playback screen.
    private func recordAndStop(scenario: String, file: StaticString = #filePath, line: UInt = #line) throws -> XCUIApplication {
        let app = launch(scenario: scenario)

        app.open(try XCTUnwrap(URL(string: "reflect://write")))
        XCTAssertTrue(element("reflection.editor", in: app).waitForExistence(timeout: timeout), file: file, line: line)

        // The editor's voice button has no label of its own, so VoiceOver and XCUITest see the
        // SF Symbol name.
        let voiceButton = app.buttons["waveform"].firstMatch
        XCTAssertTrue(voiceButton.waitForExistence(timeout: timeout), "No voice button in the editor", file: file, line: line)
        voiceButton.tap()
        XCTAssertTrue(element("voice.recorder", in: app).waitForExistence(timeout: timeout), file: file, line: line)

        element("voice.record", in: app).tap()
        allowMicrophoneIfAsked()

        let stop = element("voice.stop", in: app)
        XCTAssertTrue(stop.waitForExistence(timeout: timeout), "Recording did not start", file: file, line: line)
        // Long enough for the recorder to write some audio.
        Thread.sleep(forTimeInterval: 1.5)
        stop.tap()

        XCTAssertTrue(
            app.navigationBars.buttons["Done"].waitForExistence(timeout: timeout),
            "The playback screen did not show after stop",
            file: file,
            line: line
        )
        return app
    }

    private func launch(scenario: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uiTesting",
            "-uiTestingSpeech", scenario,
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

    /// The microphone prompt comes from SpringBoard, only on the first recording on this simulator.
    private func allowMicrophoneIfAsked() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.alerts.buttons["Allow"]
        if allow.waitForExistence(timeout: 3) {
            allow.tap()
        }
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
