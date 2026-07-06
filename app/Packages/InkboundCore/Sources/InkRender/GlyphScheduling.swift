import Foundation
import CoreGraphics

/// Per-Book hand parameters (which hand a Book uses comes from its server-side
/// definition; these are the timing constants the glyph engine needs).
public struct HandProfile: Equatable, Sendable {
    /// Path units drawn per second — the "pen pace."
    public var penPace: CGFloat
    public var interGlyphPause: TimeInterval
    public var wordPause: TimeInterval

    public init(penPace: CGFloat = 900, interGlyphPause: TimeInterval = 0.02, wordPause: TimeInterval = 0.12) {
        precondition(penPace > 0)
        self.penPace = penPace
        self.interGlyphPause = interGlyphPause
        self.wordPause = wordPause
    }
}

public struct GlyphMetric: Equatable, Sendable {
    public var pathLength: CGFloat
    /// True for the glyph that ends a word (schedules the word pause after it).
    public var endsWord: Bool

    public init(pathLength: CGFloat, endsWord: Bool = false) {
        self.pathLength = pathLength
        self.endsWord = endsWord
    }
}

/// One glyph's slot in the stroke schedule, relative to schedule start.
public struct GlyphStrokeFrame: Equatable, Sendable {
    public var index: Int
    public var startTime: TimeInterval
    public var duration: TimeInterval

    public init(index: Int, startTime: TimeInterval, duration: TimeInterval) {
        self.index = index
        self.startTime = startTime
        self.duration = duration
    }
}

/// Timed stroke schedule (task C3): per-glyph duration ∝ path length at the
/// hand's pen pace. Pure math — the SwiftUI layer animates along it.
public enum GlyphStrokeScheduler {
    public static func schedule(_ glyphs: [GlyphMetric], hand: HandProfile) -> [GlyphStrokeFrame] {
        var frames: [GlyphStrokeFrame] = []
        frames.reserveCapacity(glyphs.count)
        var cursor: TimeInterval = 0
        for (index, glyph) in glyphs.enumerated() {
            let duration = TimeInterval(glyph.pathLength / hand.penPace)
            frames.append(GlyphStrokeFrame(index: index, startTime: cursor, duration: duration))
            cursor += duration + (glyph.endsWord ? hand.wordPause : hand.interGlyphPause)
        }
        return frames
    }
}

/// Streams complete words out of arbitrary ink deltas so the glyph engine can
/// paginate on word boundaries (partial words never render).
public struct WordStreamPaginator: Sendable {
    private var buffer = ""

    public init() {}

    /// Feed a delta; get back the words it completed.
    public mutating func consume(_ delta: String) -> [String] {
        buffer += delta
        var words: [String] = []
        while let boundary = buffer.firstIndex(where: \.isWhitespace) {
            let word = String(buffer[..<boundary])
            if !word.isEmpty { words.append(word) }
            buffer.removeSubrange(...boundary)
        }
        return words
    }

    /// End of stream: whatever remains is the last word.
    public mutating func flush() -> String? {
        defer { buffer = "" }
        return buffer.isEmpty ? nil : buffer
    }
}
