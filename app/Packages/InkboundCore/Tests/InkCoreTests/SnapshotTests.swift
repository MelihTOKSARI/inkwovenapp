import Foundation
import CoreGraphics
import Testing
@testable import InkCore

private struct StubRasterizer: DrawingRasterizing {
    var payload: Data
    func rasterize(cropRect: CGRect, targetPixelSize: CGSize) throws -> Data { payload }
}

@Suite("Snapshot pipeline (task B4)")
struct SnapshotTests {
    let canvas = CGRect(x: 0, y: 0, width: 2000, height: 2800)

    @Test("crop is the padded union of new strokes, clamped to the canvas")
    func cropUnionPaddedClamped() {
        let strokes = [CGRect(x: 100, y: 100, width: 50, height: 20),
                       CGRect(x: 300, y: 400, width: 10, height: 10)]
        let crop = SnapshotPlanner.cropRect(newStrokeBounds: strokes, canvasBounds: canvas, padding: 24)
        #expect(crop == CGRect(x: 76, y: 76, width: 258, height: 358))

        // A stroke at the canvas edge must not pad outside it.
        let edge = SnapshotPlanner.cropRect(newStrokeBounds: [CGRect(x: 0, y: 0, width: 10, height: 10)],
                                            canvasBounds: canvas, padding: 24)
        #expect(edge == CGRect(x: 0, y: 0, width: 34, height: 34))
    }

    @Test("no new strokes → nil crop")
    func emptyStrokesNilCrop() {
        #expect(SnapshotPlanner.cropRect(newStrokeBounds: [], canvasBounds: canvas) == nil)
        #expect(SnapshotPlanner.cropRect(newStrokeBounds: [.null], canvasBounds: canvas) == nil)
    }

    @Test("downscale clamps the long edge to 1024, preserving aspect")
    func downscaleLongEdge() {
        let size = SnapshotPlanner.targetPixelSize(for: CGSize(width: 2048, height: 1024))
        #expect(size == CGSize(width: 1024, height: 512))
        // Already small enough → untouched.
        let small = SnapshotPlanner.targetPixelSize(for: CGSize(width: 800, height: 600))
        #expect(small == CGSize(width: 800, height: 600))
    }

    @Test("identical raster output → skipDuplicate (re-rolls never re-billed)")
    func digestDedupe() throws {
        let processor = SnapshotProcessor(rasterizer: StubRasterizer(payload: Data("same-ink".utf8)))
        let strokes = [CGRect(x: 10, y: 10, width: 100, height: 40)]

        let first = try processor.process(newStrokeBounds: strokes, canvasBounds: canvas, previousDigest: nil)
        guard case .send(let payload) = first else {
            Issue.record("expected send, got \(first)")
            return
        }
        let second = try processor.process(newStrokeBounds: strokes, canvasBounds: canvas, previousDigest: payload.digest)
        #expect(second == .skipDuplicate(digest: payload.digest))
    }

    @Test("processing with no new ink throws")
    func noNewInkThrows() {
        let processor = SnapshotProcessor(rasterizer: StubRasterizer(payload: Data()))
        #expect(throws: SnapshotError.noNewInk) {
            try processor.process(newStrokeBounds: [], canvasBounds: canvas, previousDigest: nil)
        }
    }
}
