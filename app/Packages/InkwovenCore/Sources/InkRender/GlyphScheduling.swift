import Foundation
import CoreGraphics

/// Per-Book hand parameters (which hand a Book uses comes from its server-side
/// definition; these are the timing constants the glyph engine needs).
public struct HandProfile: Equatable, Sendable {
    /// Path units drawn per second — the "pen pace."
    /// `private(set)` so the init's clamp is the only way values get in.
    public private(set) var penPace: CGFloat
    public private(set) var interGlyphPause: TimeInterval
    public private(set) var wordPause: TimeInterval

    /// Slowest pace we will honor. A zero or negative pace would divide path
    /// length into an infinite or negative duration and hang the page.
    public static let minimumPenPace: CGFloat = 1

    /// Hand parameters come from the Book's server-side definition, so a bad
    /// value must clamp rather than trap. Pen pace floors at
    /// `minimumPenPace`; pauses floor at zero (a negative pause would run the
    /// schedule backwards).
    public init(penPace: CGFloat = 900, interGlyphPause: TimeInterval = 0.02, wordPause: TimeInterval = 0.12) {
        self.penPace = penPace.isFinite ? max(Self.minimumPenPace, penPace) : Self.minimumPenPace
        self.interGlyphPause = interGlyphPause.isFinite ? max(0, interGlyphPause) : 0
        self.wordPause = wordPause.isFinite ? max(0, wordPause) : 0
    }
}

public struct GlyphMetric: Equatable, Sendable {
    public private(set) var pathLength: CGFloat
    /// True for the glyph that ends a word (schedules the word pause after it).
    public var endsWord: Bool

    /// Lengths are measured from server-sourced text, so a NaN or negative
    /// length clamps to zero (an instantaneous glyph) instead of poisoning
    /// every subsequent `startTime` in the schedule.
    public init(pathLength: CGFloat, endsWord: Bool = false) {
        self.pathLength = pathLength.isFinite ? max(0, pathLength) : 0
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
        let lastIndex = glyphs.count - 1
        for (index, glyph) in glyphs.enumerated() {
            let duration = TimeInterval(glyph.pathLength / hand.penPace)
            frames.append(GlyphStrokeFrame(index: index, startTime: cursor, duration: duration))
            // No pause after the last glyph: a trailing wordPause is dead time
            // the page would sit through before settling.
            guard index < lastIndex else { break }
            cursor += duration + (glyph.endsWord ? hand.wordPause : hand.interGlyphPause)
        }
        return frames
    }

    /// The one true total. Consumers must read this rather than re-deriving it
    /// by summing durations and pauses — that mirror walk is what would
    /// reintroduce a trailing pause the schedule does not contain.
    public static func totalDuration(_ frames: [GlyphStrokeFrame]) -> TimeInterval {
        frames.last.map { $0.startTime + $0.duration } ?? 0
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
