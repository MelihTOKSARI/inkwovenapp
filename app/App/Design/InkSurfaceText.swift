import SwiftUI

/// The Book's words, appearing per the law of the ink: the WHOLE block
/// surfaces at once — blur falling away, a small rise — with a per-word
/// scatter of no more than the contract's 420 ms, so the ink reads as
/// settling into fibre. The absorb is the same gesture reversed.
///
/// Law II lives here: this view must never be driven glyph-by-glyph or
/// left-to-right. The scatter delays are a fixed jitter ((i·137) mod 420),
/// deliberately non-sequential — a page drinking, never a typewriter. The
/// writer's own hand is the ONLY ink that ever writes out in order.
struct InkSurfaceText: View {
    enum Phase {
        /// Not yet risen — under the paper.
        case under
        /// Standing on the page.
        case up
        /// Being drunk — going back under.
        case absorbed
    }

    let text: String
    let font: Font
    let color: Color
    var lineSpacing: CGFloat = 6
    var centered = false
    let phase: Phase
    let reduce: Bool

    /// The scatter ceiling, from the contract: no word waits longer than
    /// this before joining the crossing.
    static let scatter: Double = 0.42

    private struct Word: Identifiable {
        let id: Int
        let text: String
        /// The word's first glyph index in the whole text — the scatter
        /// seed, so re-renders never reshuffle the jitter.
        let glyphIndex: Int
    }

    private var words: [Word] {
        var out: [Word] = []
        var glyph = 0
        for (i, piece) in text.split(separator: " ", omittingEmptySubsequences: false).enumerated() {
            out.append(Word(id: i, text: String(piece) + " ", glyphIndex: glyph))
            glyph += piece.count + 1
        }
        return out
    }

    private func delay(for word: Word) -> Double {
        let raw = Double((word.glyphIndex * 137) % 420) / 1000
        return reduce ? raw * 0.35 : raw
    }

    private var crossing: Animation {
        phase == .absorbed
            ? InkMotion.Surface.sink(reduce: reduce)
            : InkMotion.Surface.rise(reduce: reduce)
    }

    var body: some View {
        InkFlowLayout(lineSpacing: lineSpacing, centered: centered) {
            ForEach(words) { word in
                Text(word.text)
                    .font(font)
                    .foregroundStyle(color)
                    .opacity(phase == .up ? 1 : 0)
                    .blur(radius: phase == .up ? 0 : InkMotion.Surface.haze)
                    .offset(y: phase == .up ? 0 : InkMotion.Surface.depth)
                    .animation(crossing.delay(delay(for: word)), value: phase)
            }
        }
        // One sentence to assistive tech, never a word salad — and never a
        // half-crossed block: the label is the whole text regardless of phase.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(text))
        .accessibilityHidden(phase != .up)
    }
}

/// Word-wrap for individually animated words. `Text` cannot carry per-word
/// modifiers, so the words are separate views and this lays them into lines —
/// leading or centred — the way the paragraph would have wrapped itself.
struct InkFlowLayout: Layout {
    var lineSpacing: CGFloat = 6
    var centered = false

    private struct Line {
        var range: Range<Int>
        var width: CGFloat
        var height: CGFloat
        var y: CGFloat
    }

    private func lines(subviews: Subviews, in width: CGFloat) -> [Line] {
        var out: [Line] = []
        var start = 0
        var x: CGFloat = 0
        var lineHeight: CGFloat = 0
        var y: CGFloat = 0
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                out.append(Line(range: start..<index, width: x, height: lineHeight, y: y))
                y += lineHeight + lineSpacing
                start = index
                x = 0
                lineHeight = 0
            }
            x += size.width
            lineHeight = max(lineHeight, size.height)
        }
        if start < subviews.count {
            out.append(Line(range: start..<subviews.count, width: x, height: lineHeight, y: y))
        }
        return out
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 600
        let laid = lines(subviews: subviews, in: width)
        guard let last = laid.last else { return .zero }
        let widest = laid.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? widest, height: last.y + last.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let laid = lines(subviews: subviews, in: bounds.width)
        for line in laid {
            var x = bounds.minX + (centered ? (bounds.width - line.width) / 2 : 0)
            for index in line.range {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: bounds.minY + line.y + (line.height - size.height)),
                    anchor: .topLeading,
                    proposal: .unspecified
                )
                x += size.width
            }
        }
    }
}
