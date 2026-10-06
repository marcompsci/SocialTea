import XCTest

/// Walks every screen and saves a screenshot of each one.
/// On CI, screenshots are written to $SCREENSHOT_DIR (passed as TEST_RUNNER_SCREENSHOT_DIR).
final class SocialTeaUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = true
        app = XCUIApplication()
    }

    // MARK: Helpers

    private func snap(_ name: String, wait: Double = 1.2) {
        Thread.sleep(forTimeInterval: wait)
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"], !dir.isEmpty {
            let url = URL(fileURLWithPath: dir).appendingPathComponent("\(name).png")
            try? shot.pngRepresentation.write(to: url)
        }
    }

    private func element(containing text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    private func tab(_ name: String) {
        let button = app.tabBars.buttons[name]
        XCTAssertTrue(button.waitForExistence(timeout: 5), "Tab \(name) missing")
        button.tap()
    }

    private func chip(_ id: String) {
        let chip = app.buttons["chip.\(id)"]
        guard chip.waitForExistence(timeout: 3) else { XCTFail("Chip \(id) missing"); return }
        var tries = 0
        while !chip.isHittable && tries < 4 {
            app.scrollViews["chipRow"].firstMatch.swipeLeft()
            tries += 1
        }
        chip.tap()
    }

    private func platform(_ name: String) {
        let seg = app.segmentedControls.buttons[name].firstMatch
        if seg.waitForExistence(timeout: 3) { seg.tap() } else { XCTFail("Platform \(name) missing") }
    }

    // MARK: Baseline snapshot (what a fresh launch shows)

    func testBaselineSnapshot() {
        app.launch()

        // First launch shows the intro; walk through it.
        let next = app.buttons["Continue"].firstMatch
        if next.waitForExistence(timeout: 4) {
            var page = 0
            while next.exists && page < 6 {
                snap("00-onboarding-\(page)", wait: 0.8)
                next.tap()
                page += 1
            }
            snap("00-onboarding-\(page)", wait: 0.8)
            let start = app.buttons["Get Started"].firstMatch
            if start.waitForExistence(timeout: 2) { start.tap() }
        }
        XCTAssertTrue(element(containing: "2 loaded platforms").waitForExistence(timeout: 5), "Status label wrong")
        XCTAssertTrue(element(containing: "3,977").waitForExistence(timeout: 5), "Baseline followers missing")
        XCTAssertTrue(element(containing: "777").exists, "Baseline following missing")
        XCTAssertTrue(element(containing: "191").exists, "Baseline not-following-back missing")
        snap("01-dashboard-baseline")
        app.swipeUp()
        snap("02-dashboard-baseline-cards")

        tab("Lists")
        snap("03-lists-baseline-counts-only")
        platform("Facebook")
        snap("04-lists-baseline-facebook")

        tab("Cleanup")
        platform("Instagram")
        snap("05-cleanup-baseline-needs-names")

        tab("Guide")
        snap("06-guide-top")
        app.swipeUp()
        snap("07-guide-steps")
        app.swipeUp()
        snap("08-guide-meanings")
        app.swipeUp()
        app.swipeUp()
        snap("09-guide-promise")
    }

    // MARK: Demo walkthrough

    func testDemoWalkthrough() {
        app.launchArguments = ["-UITestDemo", "-UITestSkipOnboarding"]
        app.launch()

        XCTAssertTrue(element(containing: "3 loaded platforms").waitForExistence(timeout: 5), "Demo status label wrong")
        snap("10-dashboard-demo")

        // Settings sheet
        app.buttons["Settings"].firstMatch.tap()
        snap("11-settings")
        app.buttons["Done"].firstMatch.tap()

        // Theme customizer
        let theme = app.buttons["Customize theme"].firstMatch
        if theme.waitForExistence(timeout: 3) {
            theme.tap()
            snap("13-theme-customizer")
            app.buttons["Done"].firstMatch.tap()
        }

        // Import sheet for Instagram
        let importButton = app.buttons["Import / replace"].firstMatch
        if importButton.waitForExistence(timeout: 3) {
            importButton.tap()
            snap("12-import-instagram")
            app.buttons["Done"].firstMatch.tap()
        } else {
            XCTFail("Import button missing")
        }

        // Lists: every view on Instagram
        tab("Lists")
        platform("Instagram")
        let views = ["notFollowingBack", "fans", "mutuals", "unfollowed", "newFollowers", "goneQuiet"]
        for (i, v) in views.enumerated() {
            chip(v)
            snap("2\(i)-lists-instagram-\(v)")
        }

        // Search
        app.buttons["chip.notFollowingBack"].firstMatch.tap()
        app.swipeDown()
        let search = app.searchFields.firstMatch
        if search.waitForExistence(timeout: 3) {
            search.tap()
            search.typeText("coral")
            snap("27-lists-search")
            app.buttons["Cancel"].firstMatch.tap()
            if app.keyboards.firstMatch.waitForExistence(timeout: 1) {
                app.buttons["Cancel"].firstMatch.tap()
            }
        } else {
            XCTFail("Search field missing")
        }

        // TikTok and Facebook
        platform("TikTok")
        chip("notFollowingBack")
        snap("30-lists-tiktok-notFollowingBack")
        platform("Facebook")
        chip("mutuals")
        snap("31-lists-facebook-friends")
        chip("notFollowingBack")
        snap("32-lists-facebook-notFollowingBack-zero")

        // Insights
        tab("Insights")
        snap("35-insights")
        app.swipeUp()
        snap("36-insights-ratios")

        // Cleanup deck
        tab("Cleanup")
        platform("Instagram")
        snap("40-cleanup-deck")
        let queue = app.buttons["Queue to unfollow"].firstMatch
        let keep = app.buttons["Keep following"].firstMatch
        let undo = app.buttons["Undo"].firstMatch
        XCTAssertTrue(queue.waitForExistence(timeout: 3), "Cleanup buttons missing")
        queue.tap(); Thread.sleep(forTimeInterval: 0.4)
        queue.tap(); Thread.sleep(forTimeInterval: 0.4)
        keep.tap(); Thread.sleep(forTimeInterval: 0.4)
        snap("41-cleanup-after-3")
        undo.tap()
        snap("42-cleanup-after-undo")

        var taps = 0
        while keep.exists && keep.isHittable && taps < 60 {
            keep.tap()
            Thread.sleep(forTimeInterval: 0.3)
            taps += 1
        }
        XCTAssertTrue(element(containing: "Deck complete").waitForExistence(timeout: 5), "Completion screen missing")
        snap("43-cleanup-complete", wait: 0.8)

        let openQueue = app.buttons["Open queue"].firstMatch
        if openQueue.exists {
            openQueue.tap()
            snap("44-unfollow-queue")
            app.buttons["Done"].firstMatch.tap()
        }
    }

    // MARK: Free tier vs Pro

    func testProGating() {
        app.launchArguments = ["-UITestLockedSample", "-UITestSkipOnboarding"]
        app.launch()

        tab("Lists")
        platform("Instagram")
        chip("notFollowingBack")
        app.swipeUp()
        snap("60-free-lists-preview")
        XCTAssertTrue(element(containing: "Unlock SocialTea Pro").waitForExistence(timeout: 3), "Pro upsell missing in Lists")
        app.swipeDown()
        chip("unfollowed")
        snap("61-free-lists-comparison-locked")

        tab("Cleanup")
        platform("Instagram")
        snap("62-free-cleanup-locked")

        tab("Insights")
        snap("63-free-insights-locked")

        let unlock = app.buttons["Unlock SocialTea Pro"].firstMatch
        if unlock.waitForExistence(timeout: 3) {
            unlock.tap()
            snap("64-paywall", wait: 3)
            let close = app.buttons["Close"].firstMatch
            if close.exists { close.tap() }
        } else {
            XCTFail("Unlock button missing")
        }

        tab("Dashboard")
        app.buttons["Settings"].firstMatch.tap()
        snap("65-settings-pro-section")
    }
}
