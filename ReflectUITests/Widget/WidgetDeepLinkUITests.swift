import XCTest

/// Opens each Quick Actions widget URL in the running app and checks where it lands.
///
/// URLs are string literals on purpose: the test checks the `reflect://<host>` contract the
/// widget ships with, not whatever `WidgetDeepLink` currently builds.
///
/// Launch state comes from the app's `-uiTesting` hook (in-memory store, one seeded Learning)
/// plus argument-domain UserDefaults, which override the stored values for this launch only.
/// No permission prompt is expected: camera and voice only ask for access after a further tap
/// (camera primer "Continue", voice record button), and these tests stop before that. The camera
/// tests reset camera access before launch, so the camera link always lands on the primer. Only
/// those two reset: XCTest's reset times out after about ten resets in one test session.
///
/// Every landing state saves a screenshot (kept even on success) for the UI check on the issue.
@MainActor
final class WidgetDeepLinkUITests: XCTestCase {
    /// The Learning the `-uiTesting` hook seeds (see `ReflectApp.seedForUITestingIfNeeded`).
    private let seededLearningID = "00000000-0000-0000-0000-000000000001"
    private let landingTimeout: TimeInterval = 10
    /// How long a no-op URL gets to (wrongly) change the screen before we call it a no-op.
    private let noOpWindow: TimeInterval = 3

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Valid links, starting on the chapter (the app's usual landing page)

    func testWriteLinkFromChapterOpensReflectionEditor() throws {
        try assertLink("reflect://write", opens: "reflection.editor", from: launchOnChapter(), screenshot: "chapter-write")
    }

    func testCameraLinkFromChapterOpensCameraFlow() throws {
        // The simulator has no camera. With camera access reset to not determined, the flow's
        // first screen is the permission primer, shown before the system prompt or any camera.
        try assertLink("reflect://camera", opens: "camera.permissionPrimer", from: launchOnChapter(resettingCamera: true), screenshot: "chapter-camera")
    }

    func testVoiceLinkFromChapterOpensVoiceRecorder() throws {
        try assertLink("reflect://voice", opens: "voice.recorder", from: launchOnChapter(), screenshot: "chapter-voice")
    }

    // MARK: - Valid links, starting on the Chapters list

    func testWriteLinkFromChaptersListOpensReflectionEditor() throws {
        let app = launchOnLearningsList()
        try assertLink("reflect://write", opens: "reflection.editor", from: app, screenshot: "chapters-list-write")
    }

    func testCameraLinkFromChaptersListOpensCameraFlow() throws {
        let app = launchOnLearningsList(resettingCamera: true)
        try assertLink("reflect://camera", opens: "camera.permissionPrimer", from: app, screenshot: "chapters-list-camera")
    }

    func testVoiceLinkFromChaptersListOpensVoiceRecorder() throws {
        let app = launchOnLearningsList()
        try assertLink("reflect://voice", opens: "voice.recorder", from: app, screenshot: "chapters-list-voice")
    }

    func testInsightLinkAfterInsightsTabWasOpenedSelectsTabAndOpensCompose() throws {
        let app = launchOnLearningsList()
        // Build the Insights tab once, then go back, so its view already exists when the link lands.
        // Tabs are tapped by label: SwiftUI does not reliably give tab buttons an identifier.
        // This is navigation only; the landing checks below still assert on identifiers.
        tapTab("Insights", in: app)
        XCTAssertTrue(element("insights.tab", in: app).waitForExistence(timeout: landingTimeout))
        tapTab("Chapters", in: app)
        XCTAssertTrue(element("learnings.list", in: app).waitForExistence(timeout: landingTimeout))

        app.open(try url("reflect://insight"))

        XCTAssertTrue(element("insights.tab", in: app).waitForExistence(timeout: landingTimeout))
        XCTAssertTrue(element("insight.editor", in: app).waitForExistence(timeout: landingTimeout))
        attachScreenshot("insight-after-tab-opened", of: app)

        // A second link in the same session must open compose again, so the signal was reset.
        app.buttons["Cancel"].firstMatch.tap()
        XCTAssertTrue(element("insight.editor", in: app).waitForNonExistence(timeout: landingTimeout))
        // A signal left `true` reopens compose the next time the Insights list appears. Opening a
        // URL also makes the list appear again, so the second link alone can't catch that.
        tapTab("Chapters", in: app)
        XCTAssertTrue(element("learnings.list", in: app).waitForExistence(timeout: landingTimeout))
        tapTab("Insights", in: app)
        XCTAssertTrue(element("insights.tab", in: app).waitForExistence(timeout: landingTimeout))
        assertStaysAbsent(["insight.editor"], in: app, "Compose reopened on revisiting Insights without a new link")
        attachScreenshot("insight-revisit-after-cancel", of: app)

        app.open(try url("reflect://insight"))

        XCTAssertTrue(
            element("insight.editor", in: app).waitForExistence(timeout: landingTimeout),
            "A second reflect://insight in the same session did not open compose"
        )
        attachScreenshot("insight-second-link", of: app)
    }

    func testInsightLinkBeforeInsightsTabWasOpenedSelectsTabAndOpensCompose() throws {
        let app = launchOnLearningsList()

        app.open(try url("reflect://insight"))

        XCTAssertTrue(element("insights.tab", in: app).waitForExistence(timeout: landingTimeout))
        XCTAssertTrue(element("insight.editor", in: app).waitForExistence(timeout: landingTimeout))
        attachScreenshot("insight-before-tab-opened", of: app)
    }

    func testWriteLinkWithoutLearningsOpensAddLearning() throws {
        let app = launch(extraArguments: ["-uiTestingNoLearnings"])

        app.open(try url("reflect://write"))

        XCTAssertTrue(element("learning.form", in: app).waitForExistence(timeout: landingTimeout))
        XCTAssertFalse(element("reflection.editor", in: app).exists)
        attachScreenshot("no-learnings-write", of: app)
    }

    // MARK: - Links the app must ignore

    func testUnknownHostIsIgnored() throws {
        try assertIgnored("reflect://unknown")
    }

    func testEmptyHostIsIgnored() throws {
        try assertIgnored("reflect://")
    }

    func testForeignURLIsIgnored() throws {
        try assertIgnored("https://example.com")
    }

    // MARK: - Helpers

    private func assertLink(
        _ urlString: String,
        opens identifier: String,
        from app: XCUIApplication,
        screenshot name: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        app.open(try url(urlString))

        XCTAssertTrue(
            element(identifier, in: app).waitForExistence(timeout: landingTimeout),
            "\(urlString) did not show \(identifier)",
            file: file,
            line: line
        )
        attachScreenshot(name, of: app)
    }

    /// Opens `urlString` and checks nothing reacted: still foreground, still on the Chapters list,
    /// and none of the screens a widget link can open appeared.
    private func assertIgnored(_ urlString: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let app = launchOnLearningsList()

        app.open(try url(urlString))

        let landingScreens = ["reflection.editor", "camera.permissionPrimer", "voice.recorder", "insight.editor", "learning.form"]
        assertStaysAbsent(landingScreens, in: app, "\(urlString) opened a screen", file: file, line: line)
        XCTAssertEqual(app.state, .runningForeground, "\(urlString) moved the app out of the foreground", file: file, line: line)
        XCTAssertTrue(element("learnings.list", in: app).exists, "\(urlString) left the Chapters list", file: file, line: line)
        XCTAssertFalse(element("reflections.list", in: app).exists, "\(urlString) pushed a chapter", file: file, line: line)
        attachScreenshot("ignored-\(urlString)", of: app)
    }

    private func launchOnLearningsList(resettingCamera: Bool = false) -> XCUIApplication {
        let app = launch(resettingCamera: resettingCamera)
        XCTAssertTrue(element("learnings.list", in: app).waitForExistence(timeout: landingTimeout))
        return app
    }

    /// Starts inside the seeded chapter through the app's own state restoration.
    private func launchOnChapter(resettingCamera: Bool = false) -> XCUIApplication {
        let app = launch(lastOpenedLearningID: seededLearningID, resettingCamera: resettingCamera)
        XCTAssertTrue(element("reflections.list", in: app).waitForExistence(timeout: landingTimeout))
        return app
    }

    /// `lastOpenedLearningID` empty means no chapter to restore, so the app starts on the Chapters list.
    /// `resettingCamera` sets camera access to not determined, so the camera flow shows its primer
    /// instead of the camera or the Settings alert.
    private func launch(
        lastOpenedLearningID: String = "",
        extraArguments: [String] = [],
        resettingCamera: Bool = false
    ) -> XCUIApplication {
        let app = XCUIApplication()
        if resettingCamera {
            app.resetAuthorizationStatus(for: .camera)
        }
        app.launchArguments = [
            "-uiTesting",
            // Argument-domain overrides, so a previous run on this simulator can't change the start state.
            "-hasCompletedOnboarding", "YES",
            "-debugAlwaysShowOnboarding", "NO",
            "-lastOpenedLearningId", lastOpenedLearningID,
        ] + extraArguments
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: landingTimeout))
        return app
    }

    private func tapTab(_ label: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let tab = app.tabBars.buttons[label]
        XCTAssertTrue(tab.waitForExistence(timeout: landingTimeout), "No \(label) tab", file: file, line: line)
        tab.tap()
    }

    /// Checks that none of `identifiers` appears during the no-op window.
    private func assertStaysAbsent(
        _ identifiers: [String],
        in app: XCUIApplication,
        _ message: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let noneAppeared = identifiers.map { identifier in
            let appears = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true"), object: element(identifier, in: app))
            appears.isInverted = true
            return appears
        }
        // Inverted: `.completed` only if none of them showed up within the window.
        let result = XCTWaiter().wait(for: noneAppeared, timeout: noOpWindow)
        XCTAssertEqual(result, .completed, message, file: file, line: line)
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

    private func url(_ string: String) throws -> URL {
        try XCTUnwrap(URL(string: string), "Not a URL: \(string)")
    }
}
