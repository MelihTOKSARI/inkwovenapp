import XCTest

/// End-to-end AC for the paper engine core (B1+B2+C1 in echo mode) on the
/// design surface: open the Oracle from the shelf, one stroke on the page,
/// ~3s of pen rest, and the reply streams back in the Book's hand.
/// Requires the local proxy: `cd proxy && npm start`.
final class PageHarnessUITests: XCTestCase {
    @MainActor
    func testWriteRestAnswerLoop() throws {
        let app = XCUIApplication()
        // Skip onboarding; steady the room for the run. iPad-first: the
        // two-page landscape spread is the canonical layout.
        XCUIDevice.shared.orientation = .landscapeLeft
        // pencilSeen: this test drives the ink canvas by finger; without it
        // the no-pencil default would offer the typed page instead.
        app.launchArguments += [
            "-ink.seenOnboarding", "YES", "-ink.reduceMotion", "YES",
            "-ink.pencilSeen", "YES",
        ]
        app.launch()

        // Shelf → the Oracle (first tap peeks, second opens).
        let oracle = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "The Oracle")
        ).firstMatch
        XCTAssertTrue(oracle.waitForExistence(timeout: 5), "the Oracle should stand on the shelf")
        oracle.tap()
        oracle.tap()

        let canvas = app.otherElements["ink-canvas"].firstMatch
        XCTAssertTrue(canvas.waitForExistence(timeout: 5), "the page should be open")

        // One handwritten stroke (finger input — Pencil never required).
        let start = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.4))
        let end = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end)

        // Idle-send commits at ~3s of rest; the echo reply streams after.
        let reply = app.staticTexts["reply-pane"]
        XCTAssertTrue(
            reply.waitForExistence(timeout: 20),
            "a reply should stream in (page status: \(canvas.value ?? "?"))"
        )
        let answered = NSPredicate(format: "label CONTAINS %@", "The page drinks your ink")
        expectation(for: answered, evaluatedWith: reply)
        waitForExpectations(timeout: 20)
    }
}
