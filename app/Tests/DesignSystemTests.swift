import Testing
import Foundation
import SwiftUI
import UIKit
import PencilKit
import InkCore
@testable import Inkwoven

/// The design layer's two silent failure modes: a face that never registered
/// (the room renders in San Francisco at the wrong optical size and nothing
/// says so), and a reduce-motion gate that deletes a reveal instead of
/// calming it.
@MainActor
@Suite("Design system")
struct DesignSystemTests {
    /// Every PostScript name InkFont and the Books ask for. `Font.custom`
    /// falls back silently, so nothing at runtime notices a missing file —
    /// only this, and the debug assertion inside `InkFont.face(_:)`.
    private static let declaredFaces = [
        "CormorantGaramond-SemiBold",
        "CormorantGaramond-MediumItalic",
        "EBGaramond-Regular",
        "EBGaramond-Medium",
        "EBGaramond-SemiBold",
        "EBGaramond-Italic",
        "Tangerine-Bold",
    ]

    @Test("every face InkFont names is registered in the bundle")
    func inkFontFacesResolve() {
        for name in Self.declaredFaces {
            #expect(UIFont(name: name, size: 12) != nil, "unregistered face: \(name)")
        }
    }

    @Test("every Book's script hand is registered in the bundle")
    func bookHandsResolve() {
        for book in Book.all {
            #expect(
                UIFont(name: book.hand, size: 12) != nil,
                "\(book.name) writes in an unregistered hand: \(book.hand)"
            )
        }
    }

    /// The custom faces must also participate in Dynamic Type. A fixed-size
    /// UIFont scales to itself; a metrics-scaled one grows.
    @Test("the typed hand's font scales with Dynamic Type")
    func typedHandScales() throws {
        let base = try #require(UIFont(name: "Caveat-Regular", size: 28))
        let metrics = UIFontMetrics(forTextStyle: .body)
        let large = metrics.scaledFont(
            for: base,
            compatibleWith: UITraitCollection(preferredContentSizeCategory: .accessibilityExtraLarge)
        )
        let small = metrics.scaledFont(
            for: base,
            compatibleWith: UITraitCollection(preferredContentSizeCategory: .large)
        )
        #expect(small.pointSize == 28, "the handoff's size must survive at the default setting")
        #expect(large.pointSize > small.pointSize, "the one surface the writer types into must grow")
    }

    // MARK: - Reduce motion

    @Test("the gate calms a travelling animation but never removes it")
    func gateCalmsRatherThanDeletes() {
        let spring = Animation.spring(response: 0.55, dampingFraction: 0.62)
        #expect(InkMotion.gated(spring, reduce: false) == spring)
        #expect(InkMotion.gated(spring, reduce: true) == InkMotion.calm)
        // The reduced form is still an animation — the ink arrives, it just
        // stops travelling.
        #expect(InkMotion.gated(spring, reduce: true) != spring)
    }

    @Test("ambient decoration is the one thing that stops outright")
    func ambientStops() {
        let pulse = Animation.easeInOut(duration: 3.2).repeatForever(autoreverses: true)
        #expect(InkMotion.ambient(pulse, reduce: false) != nil)
        #expect(InkMotion.ambient(pulse, reduce: true) == nil)
    }

    // MARK: - Ink thumbnails

    private func oneStroke() -> PKDrawing {
        let points = (0..<6).map { i in
            PKStrokePoint(
                location: CGPoint(x: 40 + CGFloat(i) * 10, y: 90),
                timeOffset: Double(i) * 0.02,
                size: CGSize(width: 4, height: 4),
                opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2
            )
        }
        let path = PKStrokePath(controlPoints: points, creationDate: .now)
        return PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: .black), path: path)])
    }

    private func entry(_ drawing: PKDrawing) -> PageArchive.Entry {
        PageArchive.Entry(
            id: UUID(), bookID: BookID.oracle.rawValue, createdAt: .now,
            strokeData: drawing.dataRepresentation(), typedText: nil,
            replyText: "The harvest holds."
        )
    }

    @Test("an archived entry rasterizes once and is served from the cache after")
    func thumbnailIsMemoized() throws {
        let archived = entry(oneStroke())
        let first = try #require(InkThumbnail.image(for: archived))
        let second = try #require(InkThumbnail.image(for: archived))
        // Identity, not equality: the second call must not have re-decoded the
        // PKDrawing and re-rastered it on the main actor.
        #expect(first === second)
    }

    @Test("an empty drawing yields no thumbnail, so the typed hand shows instead")
    func emptyDrawingHasNoThumbnail() {
        #expect(InkThumbnail.image(for: entry(PKDrawing())) == nil)
    }
}
