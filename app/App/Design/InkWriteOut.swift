import SwiftUI

/// The pen that writes the Book's answer onto the page — law II of the ink
/// (CLAUDE.md): answers are never placed, they write themselves, glyph by
/// glyph, a nib at the head.
///
/// The interactor streams text in arbitrary deltas; this drives a reveal
/// frontier through it at the contract's pace (34ms a glyph, jittered, the
/// pen breathing at punctuation). The whole buffer is laid out invisibly so
/// wrapping settles before glyphs surface — and while the stream is open the
/// frontier stops short of the trailing partial word, so a word only begins
/// to appear once it can finish without reflowing the line it sits on.
@MainActor @Observable
final class InkWriteOut {
    /// Everything buffered so far. The view lays this out in full; glyphs at
    /// `revealed` and beyond render clear.
    private(set) var laidText = ""
    /// The laid text as grapheme clusters, so the frontier counts what the
    /// eye counts (a family emoji is one glyph, not eleven scalars).
    private(set) var laidGlyphs: [Character] = []
    /// How many glyphs have surfaced.
    private(set) var revealed = 0
    /// The pen is out: glyphs still to come, or the stream still open.
    private(set) var writing = false

    private var target = 0
    private var streamClosed = true
    private var reduce = false
    private var ticker: Task<Void, Never>?
    /// Bumped on begin/restore so a sleeping ticker from the previous
    /// exchange wakes, sees a stale world, and dies without touching it.
    private var generation = 0

    /// A fresh exchange: the last answer is gone, the pen is poised.
    func begin() {
        generation += 1
        ticker?.cancel()
        ticker = nil
        laidText = ""
        laidGlyphs = []
        revealed = 0
        target = 0
        streamClosed = true
        writing = false
    }

    /// A restored or archived reply stands at once — the performance already
    /// happened; a revisit never re-runs it.
    func restore(_ text: String) {
        generation += 1
        ticker?.cancel()
        ticker = nil
        laidText = text
        laidGlyphs = Array(text)
        revealed = laidGlyphs.count
        target = revealed
        streamClosed = true
        writing = false
    }

    /// Feed the current buffer. `complete` marks the stream closed: the
    /// frontier may then run to the very end, trailing partial word and all.
    func sync(text: String, complete: Bool, reduce: Bool) {
        self.reduce = reduce
        guard text != laidText || complete != streamClosed else { return }
        laidText = text
        laidGlyphs = Array(text)
        streamClosed = complete
        if revealed > laidGlyphs.count { revealed = laidGlyphs.count }
        target = complete ? laidGlyphs.count : safeFrontier()
        tick()
    }

    /// The last index the frontier may reach while the stream is open: just
    /// past the final whitespace, so an unfinished word never starts.
    private func safeFrontier() -> Int {
        var i = laidGlyphs.count - 1
        while i >= 0, !laidGlyphs[i].isWhitespace { i -= 1 }
        return i + 1
    }

    private func tick() {
        writing = !streamClosed || revealed < target
        guard ticker == nil, revealed < target else { return }
        let gen = generation
        ticker = Task { [weak self] in
            while let self, !Task.isCancelled, self.generation == gen, self.revealed < self.target {
                let surfaced = self.revealed
                self.revealed = surfaced + 1
                let pause = self.delayAfterRevealing(surfaced)
                try? await Task.sleep(for: .seconds(pause))
            }
            guard let self, self.generation == gen else { return }
            self.ticker = nil
            self.writing = !self.streamClosed || self.revealed < self.target
        }
    }

    /// The hand's pace: base glyph time with deterministic jitter, a breath
    /// after stops, a half-breath after commas, a quickening into spaces —
    /// the design's cadence, folded (never skipped) under Reduce Motion.
    private func delayAfterRevealing(_ index: Int) -> Double {
        var pause = InkMotion.Script.folded(
            InkMotion.Script.glyph + InkMotion.Script.jitter(index + 1),
            reduce: reduce
        )
        let glyph = laidGlyphs[index]
        if ".—?!;".contains(glyph) || glyph.isNewline {
            pause += InkMotion.Script.folded(InkMotion.Script.stopPause, reduce: reduce)
        } else if glyph == "," {
            pause += InkMotion.Script.folded(InkMotion.Script.commaPause, reduce: reduce)
        }
        if index + 1 < laidGlyphs.count, laidGlyphs[index + 1] == " " {
            pause = max(0.014, pause * 0.7)
        }
        return max(0.012, pause)
    }
}
