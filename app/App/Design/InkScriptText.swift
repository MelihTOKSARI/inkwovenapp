import SwiftUI

/// The Book's answer as it stands on the page: a centred column of script,
/// laid out word by word so a line never reflows once its ink is down,
/// each glyph surfacing at the write-out's pace with a nib at the head —
/// and, when the page takes it back, absorbed word by word on the
/// contract's scatter (laws I and II, CLAUDE.md).
struct InkScriptText: View {
    /// The full buffered text (unrevealed glyphs lay out clear).
    let text: String
    /// Glyphs surfaced so far.
    let revealed: Int
    /// The pen is out — the freshest glyphs stay wet and the nib shows.
    let writing: Bool
    /// The page is drinking this answer.
    let absorbing: Bool
    let hand: Font
    let ink: Color
    /// The hand's point size — spacing rides on it so every Book's script
    /// breathes in proportion.
    var glyphSize: CGFloat = 24

    @Environment(\.reduceInkMotion) private var reduceMotion

    var body: some View {
        let paragraphs = Self.tokenize(text)
        VStack(alignment: .center, spacing: glyphSize * 0.55) {
            if paragraphs.isEmpty, writing {
                // The pen has touched down ahead of the first word.
                NibDot(ink: ink)
            }
            ForEach(paragraphs) { paragraph in
                CenteredFlow(hSpacing: glyphSize * 0.3, vSpacing: 7) {
                    ForEach(paragraph.words) { word in
                        wordView(word)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func wordView(_ token: WordToken) -> some View {
        let shown = max(0, min(token.count, revealed - token.start))
        // Wet ink trails the head by two glyphs — only while the pen is out.
        let wetFloor = max(0, min(token.count, revealed - 2 - token.start))
        let wet = writing ? shown - wetFloor : 0
        let nib = writing && revealed > token.start && revealed <= token.start + token.count
        return WordInk(
            word: token.text, shown: shown, wet: wet, nib: nib,
            hand: hand, ink: ink
        )
        .equatable()
        .opacity(absorbing ? 0 : 1)
        .blur(radius: absorbing && !reduceMotion ? InkMotion.Surface.haze : 0)
        .offset(y: absorbing && !reduceMotion ? InkMotion.Surface.depth : 0)
        .animation(
            absorbing
                ? InkMotion.Surface.sink(reduce: reduceMotion)
                    .delay(InkMotion.Script.scatter(token.ordinal, reduce: reduceMotion))
                : InkMotion.Surface.rise(reduce: reduceMotion),
            value: absorbing
        )
    }

    // MARK: - Tokens

    struct WordToken: Identifiable, Equatable {
        /// Global glyph index of the first character — stable under an
        /// append-only stream, so it doubles as identity.
        let start: Int
        let text: String
        let count: Int
        /// Word ordinal across the whole reply, for the absorb scatter.
        let ordinal: Int
        var id: Int { start }
    }

    struct ParagraphToken: Identifiable, Equatable {
        let start: Int
        let words: [WordToken]
        var id: Int { start }
    }

    /// One walk over the glyphs: words split on spaces, paragraphs on
    /// newlines, every token carrying its global glyph offset so reveal
    /// counts map straight onto the layout.
    static func tokenize(_ text: String) -> [ParagraphToken] {
        var paragraphs: [ParagraphToken] = []
        var words: [WordToken] = []
        var word = ""
        var wordStart = 0
        var paragraphStart = 0
        var ordinal = 0
        var index = 0

        func closeWord() {
            guard !word.isEmpty else { return }
            words.append(WordToken(start: wordStart, text: word, count: word.count, ordinal: ordinal))
            ordinal += 1
            word = ""
        }
        func closeParagraph(at next: Int) {
            closeWord()
            if !words.isEmpty {
                paragraphs.append(ParagraphToken(start: paragraphStart, words: words))
                words = []
            }
            paragraphStart = next
        }

        for glyph in text {
            if glyph.isNewline {
                closeParagraph(at: index + 1)
            } else if glyph == " " {
                closeWord()
            } else {
                if word.isEmpty { wordStart = index }
                word.append(glyph)
            }
            index += 1
        }
        closeParagraph(at: index)
        return paragraphs
    }
}

/// One word of the reply. Equatable so the thirty-times-a-second reveal
/// tick re-renders only the word under the nib — settled words compare
/// equal and keep their bodies.
private struct WordInk: View, Equatable {
    let word: String
    let shown: Int
    let wet: Int
    let nib: Bool
    let hand: Font
    let ink: Color

    nonisolated static func == (a: WordInk, b: WordInk) -> Bool {
        a.word == b.word && a.shown == b.shown && a.wet == b.wet && a.nib == b.nib
    }

    var body: some View {
        HStack(spacing: 5) {
            Text(attributed)
                .font(hand)
            if nib {
                NibDot(ink: ink)
            }
        }
    }

    /// Three runs, never per-glyph attributes: settled ink, the wet head,
    /// and the clear tail that holds the layout open.
    private var attributed: AttributedString {
        let glyphs = Array(word)
        let settled = max(0, shown - wet)
        var out = AttributedString()
        if settled > 0 {
            var run = AttributedString(String(glyphs[0..<settled]))
            run.foregroundColor = ink.opacity(0.93)
            out += run
        }
        if shown > settled {
            var run = AttributedString(String(glyphs[settled..<shown]))
            run.foregroundColor = ink.opacity(0.6)
            out += run
        }
        if glyphs.count > shown {
            var run = AttributedString(String(glyphs[shown...]))
            run.foregroundColor = .clear
            out += run
        }
        return out
    }
}

/// The nib at the writing head: a drop of ink that swells and settles on
/// the design's 0.85s breath. Under Reduce Motion it stands steady.
struct NibDot: View {
    let ink: Color
    @Environment(\.reduceInkMotion) private var reduceMotion
    @State private var beat = false

    var body: some View {
        Circle()
            .fill(ink)
            .frame(width: 5, height: 5)
            .scaleEffect(beat ? 1.05 : 0.85)
            .opacity(beat ? 0.95 : 0.3)
            .shadow(color: ink.opacity(0.55), radius: 4)
            .onAppear {
                guard !reduceMotion else {
                    beat = true
                    return
                }
                withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) {
                    beat = true
                }
            }
    }
}

/// A wrapping line layout that centres every row — the flow the reply's
/// words run in. Word views keep their measured size; rows break at the
/// proposed width and centre within it.
struct CenteredFlow: Layout {
    var hSpacing: CGFloat
    var vSpacing: CGFloat

    private struct Row {
        var range: Range<Int>
        var width: CGFloat
        var height: CGFloat
    }

    private func rows(fitting width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var index = 0
        while index < subviews.count {
            let start = index
            var rowWidth: CGFloat = 0
            var rowHeight: CGFloat = 0
            while index < subviews.count {
                let size = subviews[index].sizeThatFits(.unspecified)
                let grown = rowWidth == 0 ? size.width : rowWidth + hSpacing + size.width
                if rowWidth > 0, grown > width { break }
                rowWidth = grown
                rowHeight = max(rowHeight, size.height)
                index += 1
            }
            rows.append(Row(range: start..<index, width: rowWidth, height: rowHeight))
        }
        return rows
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let limit = proposal.width ?? .infinity
        let laid = rows(fitting: limit, subviews: subviews)
        let height = laid.reduce(0) { $0 + $1.height }
            + vSpacing * CGFloat(max(0, laid.count - 1))
        let natural = laid.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? natural, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let laid = rows(fitting: bounds.width, subviews: subviews)
        var y = bounds.minY
        for row in laid {
            var x = bounds.minX + (bounds.width - row.width) / 2
            for index in row.range {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                    anchor: .topLeading,
                    proposal: .unspecified
                )
                x += size.width + hSpacing
            }
            y += row.height + vSpacing
        }
    }
}
