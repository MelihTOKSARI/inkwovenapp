import XCTest

/// Pen-first, keys as fallback (task H1, revised): when a pencil has been
/// seen (`-ink.pencilSeen YES`), a keyboard appearing anywhere is still a
/// launch-blocking bug. When no pencil exists (simulator, pencil-less iPad),
/// the keyboard is the sanctioned fallback hand — onboarding and the page
/// must offer it.
final class KeyboardAuditUITests: XCTestCase {
    // MARK: - Pencil present: ink-only, no keyboard anywhere

    @MainActor
    func testOnboardingIsPenFirstNoKeyboardWhenPencilSeen() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-ink.seenOnboarding", "NO", "-ink.startScreen", "onboarding",
            "-ink.reduceMotion", "YES", "-ink.pencilSeen", "YES",
            // Clears any signature persisted by an earlier test in this container.
            "-ink.resetOnboarding", "YES",
        ]
        app.launch()

        // Intro renders instantly under reduce-motion; the flyleaf follows.
        let flyleaf = app.otherElements["signature-canvas"].firstMatch
        XCTAssertTrue(flyleaf.waitForExistence(timeout: 5), "the flyleaf should be on the page")
        XCTAssertEqual(app.keyboards.count, 0, "no keyboard before signing")
        XCTAssertFalse(
            app.textFields["signature-keys"].exists,
            "the keys fallback must stand down once a pencil has been seen"
        )

        // Sign in ink (finger drag — Pencil never required). The settle
        // window holds the seal back until the hand has rested.
        let start = flyleaf.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5))
        let end = flyleaf.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.58))
        start.press(forDuration: 0.05, thenDragTo: end)
        XCTAssertEqual(app.keyboards.count, 0, "signing summoned a keyboard — launch-blocking")

        // The signature unlocks the shelf door after the ink settles.
        let seal = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "step up to the shelf")
        ).firstMatch
        XCTAssertTrue(seal.waitForExistence(timeout: 8), "signing in ink should unlock the shelf")
        XCTAssertEqual(app.keyboards.count, 0, "no keyboard anywhere in pen-first onboarding")
    }

    @MainActor
    func testBookFlowSummonsNoKeyboardWhenPencilSeen() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-ink.seenOnboarding", "YES", "-ink.startScreen", "page",
            "-ink.startBook", "oracle", "-ink.reduceMotion", "YES",
            "-ink.pencilSeen", "YES",
        ]
        app.launch()

        let canvas = app.otherElements["ink-canvas"].firstMatch
        XCTAssertTrue(canvas.waitForExistence(timeout: 5), "the page should be open")
        XCTAssertEqual(app.keyboards.count, 0)

        let start = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.4))
        let end = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end)
        XCTAssertEqual(app.keyboards.count, 0, "keyboard in a pen-first Book flow — launch-blocking")
    }

    // MARK: - No pencil: the keys are the fallback hand

    @MainActor
    func testOnboardingOffersKeysAndSealsTypedName() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-ink.seenOnboarding", "NO", "-ink.startScreen", "onboarding",
            "-ink.reduceMotion", "YES",
            "-ink.resetOnboarding", "YES",
        ]
        app.launch()

        let flyleaf = app.otherElements["signature-canvas"].firstMatch
        XCTAssertTrue(flyleaf.waitForExistence(timeout: 5), "the flyleaf should be on the page")

        // No pencil about → the SAME field takes keyboard focus on its own
        // (one field, two hands — never a second input). `app.keyboards` is
        // unreliable when the sim has a hardware keyboard attached, so the
        // proof is that typing lands without tapping anything.
        Thread.sleep(forTimeInterval: 2)
        app.typeText("Melih")

        // The settle window gives time to finish; then the seal bounces in.
        let seal = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "step up to the shelf")
        ).firstMatch
        XCTAssertTrue(seal.waitForExistence(timeout: 8), "a typed name should unlock the shelf")
    }

    @MainActor
    func testBookFlowOffersTypedPageWithoutPencil() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-ink.seenOnboarding", "YES", "-ink.startScreen", "page",
            "-ink.startBook", "oracle", "-ink.reduceMotion", "YES",
        ]
        app.launch()

        // One surface, two hands: with no pencil, the ink canvas itself
        // takes keyboard focus on its own, and typed words feed the same
        // rest cadence as ink (status → resting).
        let canvas = app.otherElements["ink-canvas"].firstMatch
        XCTAssertTrue(canvas.waitForExistence(timeout: 5), "the page should be open")
        Thread.sleep(forTimeInterval: 2)
        app.typeText("hello, page")
        let resting = NSPredicate(format: "value CONTAINS %@", "resting")
        expectation(for: resting, evaluatedWith: canvas)
        waitForExpectations(timeout: 5)
    }
}
