import XCTest

/// Opens each Quick Actions widget URL in the running app and checks where it lands.
///
/// URLs are string literals on purpose: the test checks the `reflect://<host>` contract the
/// widget ships with, not whatever `WidgetDeepLink` currently builds.
///
/// Launch state comes from the app's `-uiTesting` hook (in-memory store, one seeded Learning)
/// plus argument-domain UserDefaults, which override the stored values for this launch only.
/// No permission prompt is expected: camera and voice only ask for access after a further tap
/// (camera intro "Continue", voice record button), and these tests stop before that.
@MainActor
final class WidgetDeepLinkUITests: XCTestCase {
    /// The Learning the `-uiTesting` hook seeds (see `ReflectApp.seedForUITestingIfNeeded`).
    private let seededLearningID = "00000000-0000-0000-0000-000000000001"
    private let landingTimeout: TimeInterval = 10
    /// How long a no-op URL gets to (wrongly) change the screen before we call it a no-op.
    private let noOpWindow: TimeInterval = 3

    /// Write, camera and voice links opened while the Chapters list is on screen push the chapter
    /// but never present the editor / camera / recorder: `ReflectionListView` only reacts in
    /// `.onChange(of: widgetAction)`, which does not fire for the value it appears with.
    /// Strict, so these tests fail once the bug is fixed and the wrapper must be removed.
    private let pushedChapterDropsAction = "Widget link from the Chapters list pushes the chapter but drops the action (reported on GAR-8)"

    /// `reflect://insight` selects the Insights tab but no compose sheet appears, whether or not the
    /// tab was opened before. `InsightListView.onChange(of: composeSignal)` does not fire.
    /// Strict, like `pushedChapterDropsAction`.
    private let insightLinkDropsCompose = "Insight link selects the tab but compose never opens (reported on GAR-8)"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Valid links, starting on the chapter (the app's usual landing page)

    func testWriteLinkFromChapterOpensReflectionEditor() throws {
        try assertLink("reflect://write", opens: "reflection.editor", from: launchOnChapter())
    }

    func testCameraLinkFromChapterOpensCameraFlow() throws {
        // The simulator has no camera. With the intro not yet seen, the flow's first screen is
        // the camera intro, shown before any permission request or camera hardware check.
        try assertLink("reflect://camera", opens: "camera.intro", from: launchOnChapter())
    }

    func testVoiceLinkFromChapterOpensVoiceRecorder() throws {
        try assertLink("reflect://voice", opens: "voice.recorder", from: launchOnChapter())
    }

    // MARK: - Valid links, starting on the Chapters list

    func testWriteLinkFromChaptersListOpensReflectionEditor() throws {
        let app = launchOnLearningsList()
        XCTExpectFailure(pushedChapterDropsAction)
        try assertLink("reflect://write", opens: "reflection.editor", from: app)
    }

    func testCameraLinkFromChaptersListOpensCameraFlow() throws {
        let app = launchOnLearningsList()
        XCTExpectFailure(pushedChapterDropsAction)
        try assertLink("reflect://camera", opens: "camera.intro", from: app)
    }

    func testVoiceLinkFromChaptersListOpensVoiceRecorder() throws {
        let app = launchOnLearningsList()
        XCTExpectFailure(pushedChapterDropsAction)
        try assertLink("reflect://voice", opens: "voice.recorder", from: app)
    }

    func testInsightLinkAfterInsightsTabWasOpenedSelectsTabAndOpensCompose() throws {
        let app = launchOnLearningsList()
        // Build the Insights tab once, then go back, so its view already exists when the link lands.
        // Tab buttons carry their SF Symbol name as identifier (set by SwiftUI, not by us).
        app.tabBars.buttons["lightbulb.fill"].tap()
        XCTAssertTrue(element("insights.tab", in: app).waitForExistence(timeout: landingTimeout))
        app.tabBars.buttons["book.fill"].tap()
        XCTAssertTrue(element("learnings.list", in: app).waitForExistence(timeout: landingTimeout))

        app.open(try url("reflect://insight"))

        XCTAssertTrue(element("insights.tab", in: app).waitForExistence(timeout: landingTimeout))
        XCTExpectFailure(insightLinkDropsCompose)
        XCTAssertTrue(element("insight.editor", in: app).waitForExistence(timeout: landingTimeout))
    }

    func testInsightLinkBeforeInsightsTabWasOpenedSelectsTabAndOpensCompose() throws {
        let app = launchOnLearningsList()

        app.open(try url("reflect://insight"))

        XCTAssertTrue(element("insights.tab", in: app).waitForExistence(timeout: landingTimeout))
        XCTExpectFailure(insightLinkDropsCompose)
        XCTAssertTrue(element("insight.editor", in: app).waitForExistence(timeout: landingTimeout))
    }

    func testWriteLinkWithoutLearningsOpensAddLearning() throws {
        let app = launch(extraArguments: ["-uiTestingNoLearnings"])

        app.open(try url("reflect://write"))

        XCTAssertTrue(element("learning.form", in: app).waitForExistence(timeout: landingTimeout))
        XCTAssertFalse(element("reflection.editor", in: app).exists)
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
    }

    /// Opens `urlString` and checks nothing reacted: still foreground, still on the Chapters list,
    /// and none of the screens a widget link can open appeared.
    private func assertIgnored(_ urlString: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let app = launchOnLearningsList()

        app.open(try url(urlString))

        let landingScreens = ["reflection.editor", "camera.intro", "voice.recorder", "insight.editor", "learning.form"]
        let noneAppeared = landingScreens.map { identifier in
            let appears = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true"), object: element(identifier, in: app))
            appears.isInverted = true
            return appears
        }
        // Inverted: `.completed` only if none of the landing screens showed up within the window.
        let result = XCTWaiter().wait(for: noneAppeared, timeout: noOpWindow)
        XCTAssertEqual(result, .completed, "\(urlString) opened a screen", file: file, line: line)
        XCTAssertEqual(app.state, .runningForeground, "\(urlString) moved the app out of the foreground", file: file, line: line)
        XCTAssertTrue(element("learnings.list", in: app).exists, "\(urlString) left the Chapters list", file: file, line: line)
        XCTAssertFalse(element("reflections.list", in: app).exists, "\(urlString) pushed a chapter", file: file, line: line)
    }

    private func launchOnLearningsList() -> XCUIApplication {
        let app = launch()
        XCTAssertTrue(element("learnings.list", in: app).waitForExistence(timeout: landingTimeout))
        return app
    }

    /// Starts inside the seeded chapter through the app's own state restoration.
    private func launchOnChapter() -> XCUIApplication {
        let app = launch(lastOpenedLearningID: seededLearningID)
        XCTAssertTrue(element("reflections.list", in: app).waitForExistence(timeout: landingTimeout))
        return app
    }

    /// `lastOpenedLearningID` empty means no chapter to restore, so the app starts on the Chapters list.
    private func launch(lastOpenedLearningID: String = "", extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uiTesting",
            // Argument-domain overrides, so a previous run on this simulator can't change the start state.
            "-hasCompletedOnboarding", "YES",
            "-debugAlwaysShowOnboarding", "NO",
            "-hasSeenCameraIntro", "NO",
            "-hasSeenVoiceIntro", "YES",
            "-lastOpenedLearningId", lastOpenedLearningID,
        ] + extraArguments
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: landingTimeout))
        return app
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func url(_ string: String) throws -> URL {
        try XCTUnwrap(URL(string: string), "Not a URL: \(string)")
    }
}
