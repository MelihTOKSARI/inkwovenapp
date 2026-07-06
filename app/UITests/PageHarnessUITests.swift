import XCTest

/// End-to-end AC for the paper engine core (B1+B2+C1 in echo mode): a stroke
/// on the canvas, ~3s of pen rest, and the reply streams back. Requires the
/// local proxy: `cd proxy && npm start`.
final class PageHarnessUITests: XCTestCase {
    @MainActor
    func testWriteRestAnswerLoop() throws {
        let app = XCUIApplication()
        app.launch()

        let canvas = app.otherElements["ink-canvas"].firstMatch
        XCTAssertTrue(canvas.waitForExistence(timeout: 5), "canvas should be on screen")

        // One handwritten stroke (finger input — Pencil never required).
        let start = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.4))
        let end = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end)

        // Idle-send commits at ~3s of rest; echo reply streams after.
        let status = app.staticTexts["status-label"]
        let answered = NSPredicate(format: "label == %@", "answered")
        expectation(for: answered, evaluatedWith: status)
        waitForExpectations(timeout: 20)

        let reply = app.staticTexts["reply-pane"]
        XCTAssertTrue(reply.label.contains("The page drinks your ink"), "echo reply should have streamed in")
    }
}
