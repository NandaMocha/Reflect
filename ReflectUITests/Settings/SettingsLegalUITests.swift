import XCTest

/// Drives Settings → About → Privacy Policy / Terms of Use, starting on the Learning Chapters list.
///
/// Every state saves a screenshot (kept even on success) for the UI check on the issue.
@MainActor
final class SettingsLegalUITests: XCTestCase {
    private let timeout: TimeInterval = 10

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testAboutRowOpensAboutWithBothLegalRows() throws {
        let app = launchOnLearningList()
        openSettings(in: app)

        let aboutRow = element("settings.about", in: app)
        XCTAssertTrue(aboutRow.waitForExistence(timeout: timeout), "Settings has no About row")
        attachScreenshot("1-settings-about-row", of: app)

        aboutRow.tap()

        XCTAssertTrue(app.navigationBars["About"].waitForExistence(timeout: timeout), "About did not open")
        XCTAssertTrue(element("about.privacyPolicy", in: app).waitForExistence(timeout: timeout), "No Privacy Policy row")
        XCTAssertTrue(element("about.termsOfUse", in: app).exists, "No Terms of Use row")
        attachScreenshot("2-about-legal-rows", of: app)
    }

    func testPrivacyPolicyShowsRealContent() throws {
        let app = launchOnLearningList()
        openAbout(in: app)

        element("about.privacyPolicy", in: app).tap()

        XCTAssertTrue(app.navigationBars["Privacy Policy"].waitForExistence(timeout: timeout), "Privacy Policy did not open")
        XCTAssertTrue(element("legal.privacyPolicy", in: app).exists)
        XCTAssertTrue(app.staticTexts["Where your data lives"].exists, "Privacy Policy is missing its content")
        attachScreenshot("3-privacy-policy", of: app)
    }

    func testTermsOfUseShowsRealContent() throws {
        let app = launchOnLearningList()
        openAbout(in: app)

        element("about.termsOfUse", in: app).tap()

        XCTAssertTrue(app.navigationBars["Terms of Use"].waitForExistence(timeout: timeout), "Terms of Use did not open")
        XCTAssertTrue(element("legal.termsOfUse", in: app).exists)
        XCTAssertTrue(app.staticTexts["Your content"].exists, "Terms of Use is missing its content")
        attachScreenshot("4-terms-of-use", of: app)
    }

    // MARK: - Helpers

    /// Starts on the Learning Chapters list with the seeded chapter, past onboarding.
    private func launchOnLearningList() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uiTesting",
            // Argument-domain overrides, so a previous run on this simulator can't change the start state.
            "-hasCompletedOnboarding", "YES",
            "-debugAlwaysShowOnboarding", "NO",
            "-lastOpenedLearningId", "",
        ]
        app.launch()
        XCTAssertTrue(element("learnings.list", in: app).waitForExistence(timeout: timeout))
        return app
    }

    private func openSettings(in app: XCUIApplication) {
        let settingsButton = app.navigationBars.buttons["Settings"].firstMatch
        XCTAssertTrue(settingsButton.waitForExistence(timeout: timeout), "No Settings button")
        settingsButton.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: timeout), "Settings did not open")
    }

    private func openAbout(in app: XCUIApplication) {
        openSettings(in: app)
        let aboutRow = element("settings.about", in: app)
        XCTAssertTrue(aboutRow.waitForExistence(timeout: timeout), "Settings has no About row")
        aboutRow.tap()
        XCTAssertTrue(element("about.privacyPolicy", in: app).waitForExistence(timeout: timeout))
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
