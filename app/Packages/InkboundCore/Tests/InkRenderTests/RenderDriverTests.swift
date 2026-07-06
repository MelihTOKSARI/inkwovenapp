import Foundation
import CoreGraphics
import Testing
@testable import InkRender

@Suite("GlyphStrokeScheduler (task C3)")
struct GlyphSchedulerTests {
    @Test("duration is proportional to path length at the hand's pen pace")
    func durationProportionalToLength() {
        let hand = HandProfile(penPace: 100, interGlyphPause: 0, wordPause: 0)
        let frames = GlyphStrokeScheduler.schedule([
            GlyphMetric(pathLength: 50), GlyphMetric(pathLength: 200),
        ], hand: hand)
        #expect(frames[0].duration == 0.5)
        #expect(frames[1].duration == 2.0)
        #expect(frames[1].startTime == 0.5, "glyphs stroke sequentially")
    }

    @Test("word boundaries insert the word pause")
    func wordPauseAtBoundaries() {
        let hand = HandProfile(penPace: 100, interGlyphPause: 0.01, wordPause: 0.2)
        let frames = GlyphStrokeScheduler.schedule([
            GlyphMetric(pathLength: 100, endsWord: true),
            GlyphMetric(pathLength: 100),
        ], hand: hand)
        #expect(frames[1].startTime == 1.0 + 0.2)
    }

    @Test("schedule generation stays well under 5ms/word on this hardware")
    func schedulePerf() {
        let glyphs: [GlyphMetric] = (0..<600).map { (i: Int) in
            let length = CGFloat(50 + i % 100)
            return GlyphMetric(pathLength: length, endsWord: i % 5 == 4)
        }
        let start = ContinuousClock.now
        _ = GlyphStrokeScheduler.schedule(glyphs, hand: HandProfile())
        let elapsed = ContinuousClock.now - start
        // ~120 words scheduled; budget 5ms/word ⇒ 600ms. Being pure array math
        // it should be orders of magnitude faster; assert a generous bound.
        #expect(elapsed < .milliseconds(100))
    }
}

@Suite("WordStreamPaginator")
struct WordPaginatorTests {
    @Test("words emit only when complete — partial words never render")
    func wordsEmitOnBoundary() {
        var p = WordStreamPaginator()
        #expect(p.consume("The pa") == ["The"])
        #expect(p.consume("ge stirs") == ["page"])
        #expect(p.flush() == "stirs")
    }

    @Test("multiple boundaries in one delta all emit")
    func multipleWordsPerDelta() {
        var p = WordStreamPaginator()
        #expect(p.consume("ask me at dusk ") == ["ask", "me", "at", "dusk"])
        #expect(p.flush() == nil)
    }
}

@Suite("GlyphPathExtractor (spike A6 substrate)")
struct GlyphPathExtractorTests {
    @Test("extracts one positive-length path per visible glyph")
    func extractsPaths() {
        let paths = GlyphPathExtractor.glyphPaths(for: "hello", fontName: "Helvetica", size: 48)
        #expect(paths.count == 5)
        #expect(paths.allSatisfy { $0.length > 0 })
    }

    @Test("path length approximation: a straight line measures exactly")
    func lineLengthExact() {
        let path = CGMutablePath()
        path.move(to: .zero)
        path.addLine(to: CGPoint(x: 30, y: 40))
        #expect(path.approximateLength() == 50)
    }
}

@Suite("DevelopFrameDriver (task C4)")
struct DevelopFrameDriverTests {
    let previewData = Data([0x01])
    let finalURL = URL(fileURLWithPath: "/tmp/final.jpg")

    @Test("preview-first: preview develops immediately, final swaps in, settle")
    func previewFirstFlow() {
        var driver = DevelopFrameDriver()
        #expect(driver.handle(.previewArrived(previewData)) == [.beginPreviewDevelop(previewData)])
        #expect(driver.handle(.finalArrived(finalURL)) == [.beginFinalDevelop(finalURL)])
        #expect(driver.handle(.finalRenderCompleted) == [.settle])
        #expect(driver.phase == .settled)
    }

    @Test("final can land without a preview — never block on it")
    func finalWithoutPreview() {
        var driver = DevelopFrameDriver()
        #expect(driver.handle(.finalArrived(finalURL)) == [.beginFinalDevelop(finalURL)])
    }

    @Test("a late preview never regresses the final")
    func latePreviewIgnored() {
        var driver = DevelopFrameDriver()
        driver.handle(.finalArrived(finalURL))
        #expect(driver.handle(.previewArrived(previewData)).isEmpty)
        #expect(driver.phase == .developingFinal)
    }

    @Test("failure at any stage fails the slot")
    func failureFails() {
        var driver = DevelopFrameDriver()
        driver.handle(.previewArrived(previewData))
        #expect(driver.handle(.failed) == [.fail])
        #expect(driver.phase == .failed)
    }

    @Test("development stages progress edges → midtones → detail")
    func stagesProgress() {
        #expect(DevelopFrameDriver.Stage.at(progress: 0.1) == .edges)
        #expect(DevelopFrameDriver.Stage.at(progress: 0.5) == .midtones)
        #expect(DevelopFrameDriver.Stage.at(progress: 0.9) == .detail)
    }
}

@Suite("VideoLoopDriver (task C5)")
struct VideoLoopDriverTests {
    let remote = URL(fileURLWithPath: "/tmp/clip-remote.mp4")
    let local = URL(fileURLWithPath: "/tmp/clip-local.mp4")
    let reservation = UUID()

    @Test("download-then-loop settles the credit only once the clip is on-page")
    func happyPathSettles() {
        var driver = VideoLoopDriver()
        #expect(driver.handle(.start(remoteURL: remote, reservationID: reservation)) == [.beginDownload(remote)])
        let outputs = driver.handle(.downloadCompleted(localURL: local))
        #expect(outputs == [.loop(localURL: local), .settleCredit(reservationID: reservation)])
        #expect(driver.phase == .looping(localURL: local))
    }

    @Test("download failure refunds the credit — refund-on-failure")
    func downloadFailureRefunds() {
        var driver = VideoLoopDriver()
        driver.handle(.start(remoteURL: remote, reservationID: reservation))
        #expect(driver.handle(.downloadFailed) == [.refund(reservationID: reservation)])
        #expect(driver.phase == .failed)
    }

    @Test("playback failure after delivery does not refund (asset was delivered)")
    func playbackFailureNoRefund() {
        var driver = VideoLoopDriver()
        driver.handle(.start(remoteURL: remote, reservationID: reservation))
        driver.handle(.downloadCompleted(localURL: local))
        #expect(driver.handle(.playbackFailed).isEmpty)
    }
}
