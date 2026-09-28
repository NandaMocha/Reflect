import XCTest

/// Checks GAR-28: onboarding walks through five pages (Achievements added), and the Space detail,
/// Achievements sheet and iCloud Sync screen open with no full-screen "first open" intro.
///
/// The removed intros were `FeatureIntroView` covers whose CTA reads "Got it". A fresh user is
/// simulated by passing their old flags as `NO`, so an intro that still exists would show.
///
/// Spaces and Restore need a signed-in iCloud account. Without one the test skips those steps
/// (Space detail can't be reached, Restore is disabled) instead of passing silently.
///
/// Every state named on the issue saves a screenshot (kept even on success) for the UI check.
@MainActor
final class OnboardingIntroUITests: XCTestCase {
    private let timeout: TimeInterval = 10
    /// How long a removed intro gets to (wrongly) appear before we call it absent.
    private let introWindow: TimeInterval = 3
    /// The removed intro presets' CTA title (`FeatureIntro.buttonTitle` default).
    private let introButtonTitle = "Got it"

    private let onboardingTitles = [
        "Welcome to Reflect",
        "Learning Chapters",
        "Insights",
        "Achievements",
        "Spaces",
    ]

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Onboarding

    func testOnboardingShowsFivePagesWithAchievementsBeforeSpaces() throws {
        let app = launch(showOnboarding: true)

        XCTAssertTrue(waitUntil { self.isOnScreen(self.onboardingTitles[0], in: app) }, "Onboarding did not open on the Welcome page")
        for (index, title) in onboardingTitles.enumerated() {
            if index > 0 {
                let previous = onboardingTitles[index - 1]
                perform({ app.swipeLeft() }, until: { self.isOnScreen(title, in: app) }, unlessGone: { self.isOnScreen(previous, in: app) })
            }
            XCTAssertTrue(
                waitUntil { self.isOnScreen(title, in: app) },
                "Page \(index + 1) is not \"\(title)\""
            )
            attachScreenshot("onboarding-\(index + 1)-\(slug(title))", of: app)
        }

        // Spaces is the last page: it carries the blind-feedback rule and the only CTA.
        XCTAssertTrue(app.staticTexts["Share your own feedback first, then you see everyone else's"].exists)
        XCTAssertTrue(app.buttons["Get Started"].waitForExistence(timeout: timeout))

        // A sixth swipe must not reveal another page.
        app.swipeLeft()
        XCTAssertTrue(waitUntil { self.isOnScreen("Spaces", in: app) }, "Onboarding has more than five pages")
    }

    // MARK: - Removed first-open intros

    func testAchievementsSheetOpensWithoutIntro() throws {
        let app = launch()
        XCTAssertTrue(element("learnings.list", in: app).waitForExistence(timeout: timeout))

        let entry = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Achievements")).firstMatch
        XCTAssertTrue(waitForHittable(entry), "No Achievements entry on the Chapters list")
        // The row's button is `.plain`, so only its text and chevron take touches, not the row's
        // centre (a Spacer). Tap the label.
        let label = entry.staticTexts["Achievements"]
        let sheet = app.navigationBars["Achievements"]
        perform({ label.tap() }, until: { sheet.exists }, unlessGone: { label.isHittable })

        XCTAssertTrue(app.navigationBars["Achievements"].waitForExistence(timeout: timeout))
        assertNoIntro(in: app, "The Achievements intro still covers the sheet")
        XCTAssertTrue(waitForHittable(app.buttons["Done"]), "The Achievements sheet has no Done button")
        attachScreenshot("achievements-sheet", of: app)
    }

    func testCloudSyncOpensWithoutIntroAndShowsPrivacyFooter() throws {
        let app = openCloudSync()

        assertNoIntro(in: app, "The iCloud Sync intro still covers the screen")
        attachScreenshot("cloud-sync-top", of: app)

        let footer = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "Your data lives in your own iCloud, never on our servers.")
        ).firstMatch
        scrollUntilExists(footer, in: app)
        XCTAssertTrue(footer.exists, "The privacy footer is missing")
        XCTAssertTrue(
            footer.label.contains("Backs up learnings, reflections, photos and voice notes."),
            "The footer is missing the backup line: \(footer.label)"
        )
        attachScreenshot("cloud-sync-footer", of: app)
    }

    func testRestoreAsksForConfirmation() throws {
        let app = openCloudSync()
        let restore = element("cloudSync.restoreButton", in: app)
        scrollUntilExists(restore, in: app)
        XCTAssertTrue(restore.exists, "No Restore button on iCloud Sync")

        guard restore.isEnabled else {
            attachScreenshot("cloud-sync-restore-disabled", of: app)
            throw XCTSkip("Restore is disabled: no iCloud account (or no backup) on this simulator. Device check.")
        }
        restore.tap()

        let replaceWarning = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH %@", "This will replace all your local data")
        ).firstMatch
        XCTAssertTrue(replaceWarning.waitForExistence(timeout: timeout), "Restore did not ask for confirmation")
        attachScreenshot("cloud-sync-restore-confirmation", of: app)
    }

    func testSpaceDetailOpensWithoutIntro() throws {
        let app = launch()
        tapTab("Spaces", in: app)
        XCTAssertTrue(app.navigationBars["Spaces"].waitForExistence(timeout: timeout))
        XCTAssertFalse(app.staticTexts["Before you join Spaces"].exists, "The Spaces terms sheet covers the list")

        let firstSpace = app.cells.firstMatch
        guard firstSpace.waitForExistence(timeout: timeout) else {
            attachScreenshot("spaces-list-no-space", of: app)
            throw XCTSkip("No Space to open: Spaces need a signed-in iCloud account. Device check.")
        }
        firstSpace.tap()

        assertNoIntro(in: app, "The Spaces intro still covers the Space detail")
        XCTAssertFalse(app.staticTexts["How Spaces Work"].exists)
        attachScreenshot("space-detail", of: app)
    }

    // MARK: - Helpers

    /// Launches with argument-domain overrides, so a previous run on this simulator can't change
    /// the start state. The removed intros' flags are passed as `NO` to act as a fresh user.
    private func launch(showOnboarding: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uiTesting",
            "-hasCompletedOnboarding", showOnboarding ? "NO" : "YES",
            "-debugAlwaysShowOnboarding", showOnboarding ? "YES" : "NO",
            "-hasSeenSpaceIntro", "NO",
            "-hasSeenBadgesIntro", "NO",
            "-hasSeenCloudSyncIntro", "NO",
            // The Spaces content-terms sheet (App Review UGC rule) is not one of the removed
            // intros. Accept it up front so the Spaces steps reach the list.
            "-spaceHasAcceptedTerms", "YES",
            "-lastOpenedLearningId", "",
        ]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: timeout))
        return app
    }

    private func openCloudSync() -> XCUIApplication {
        let app = launch()
        XCTAssertTrue(element("learnings.list", in: app).waitForExistence(timeout: timeout))

        let settings = app.buttons["Settings"].firstMatch
        XCTAssertTrue(waitForHittable(settings), "No Settings button")
        let cloudSync = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "iCloud Sync")).firstMatch
        perform({ settings.tap() }, until: { cloudSync.exists }, unlessGone: { settings.isHittable })
        XCTAssertTrue(cloudSync.waitForExistence(timeout: timeout), "No iCloud Sync row in Settings")
        cloudSync.tap()

        XCTAssertTrue(app.navigationBars["iCloud Sync"].waitForExistence(timeout: timeout))
        return app
    }

    /// Runs `action` and waits for `expected`. The launch animation can swallow the first touch,
    /// so it retries, but only while `previous` is still on screen: if the screen moved somewhere
    /// else, retrying would hide a wrong result.
    private func perform(
        _ action: () -> Void,
        until expected: @escaping () -> Bool,
        unlessGone previous: () -> Bool,
        attempts: Int = 3
    ) {
        for _ in 0..<attempts {
            action()
            if waitUntil(timeout: 3, expected) || !previous() { return }
        }
    }

    /// Onboarding is a sheet over the tab view, and titles like "Learning Chapters" also exist
    /// behind it, so a title counts only when one of its matches is on screen (hittable).
    private func isOnScreen(_ title: String, in app: XCUIApplication) -> Bool {
        app.staticTexts.matching(NSPredicate(format: "label == %@", title)).allElementsBoundByIndex.contains { $0.isHittable }
    }

    private func waitUntil(timeout: TimeInterval? = nil, _ condition: @escaping () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout ?? self.timeout)
        repeat {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        } while Date() < deadline
        return condition()
    }

    /// Checks the removed intro's CTA doesn't appear during the intro window.
    private func assertNoIntro(in app: XCUIApplication, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        let appears = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true"),
            object: app.buttons[introButtonTitle]
        )
        appears.isInverted = true
        XCTAssertEqual(XCTWaiter().wait(for: [appears], timeout: introWindow), .completed, message, file: file, line: line)
    }

    private func waitForHittable(_ element: XCUIElement, timeout: TimeInterval? = nil) -> Bool {
        let hittable = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true AND hittable == true"),
            object: element
        )
        return XCTWaiter().wait(for: [hittable], timeout: timeout ?? self.timeout) == .completed
    }

    private func scrollUntilExists(_ element: XCUIElement, in app: XCUIApplication, maxSwipes: Int = 5) {
        var swipes = 0
        while !(element.exists && element.isHittable), swipes < maxSwipes {
            app.swipeUp()
            swipes += 1
        }
    }

    private func tapTab(_ label: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let tab = app.tabBars.buttons[label]
        XCTAssertTrue(tab.waitForExistence(timeout: timeout), "No \(label) tab", file: file, line: line)
        tab.tap()
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

    private func slug(_ title: String) -> String {
        title.lowercased().replacingOccurrences(of: " ", with: "-")
    }
}
