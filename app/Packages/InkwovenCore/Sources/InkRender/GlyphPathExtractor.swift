import Foundation
import CoreGraphics
import CoreText

// @unchecked: CGPath lacks a Sendable annotation. The conformance is sound
// because every path here comes from CTFontCreatePathForGlyph, which returns
// an immutable CGPath (never a CGMutablePath), and CGPath's Swift API exposes
// no mutation. The stored properties are `let` and the memberwise init is
// internal, so no other module can substitute a mutable path or reassign one
// after construction — which is what the previous `public var` spelling left
// open.
public struct GlyphPath: @unchecked Sendable {
    public let path: CGPath
    public let position: CGPoint
    public let length: CGFloat
}

/// Text → CTLine glyph runs → CGPath per glyph (task C3). The stroke schedule
/// is built from these lengths; the view layer strokes the paths.
public enum GlyphPathExtractor {
    public static func glyphPaths(for text: String, fontName: String, size: CGFloat) -> [GlyphPath] {
        let font = CTFontCreateWithName(fontName as CFString, size, nil)
        let attributed = NSAttributedString(string: text, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
        ])
        let line = CTLineCreateWithAttributedString(attributed)
        guard let runs = CTLineGetGlyphRuns(line) as? [CTRun] else { return [] }

        var result: [GlyphPath] = []
        for run in runs {
            let count = CTRunGetGlyphCount(run)
            guard count > 0 else { continue }
            var glyphs = [CGGlyph](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
            CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)

            // CoreText substitutes a font for glyphs the requested face lacks,
            // so read the run's own font. Swift's `as?`/`as!` on a CoreFoundation
            // type is an unchecked bridge — the compiler proves it "always
            // succeeds" — so a non-CTFont in this slot would sail through and
            // reach CTFontCreatePathForGlyph as a garbage reference. Verify the
            // CFTypeID for real, and fall back to the requested font otherwise;
            // that costs at most a slightly-off pace on a substituted run.
            let runFont: CTFont
            if let attrs = CTRunGetAttributes(run) as? [String: Any],
               let candidate = attrs[kCTFontAttributeName as String] as AnyObject?,
               CFGetTypeID(candidate) == CTFontGetTypeID() {
                runFont = unsafeDowncast(candidate, to: CTFont.self)
            } else {
                runFont = font
            }

            for i in 0..<count {
                guard let path = CTFontCreatePathForGlyph(runFont, glyphs[i], nil) else { continue }
                result.append(GlyphPath(path: path, position: positions[i], length: path.approximateLength()))
            }
        }
        return result
    }
}

extension CGPath {
    /// Approximate arc length: line segments exactly, curves by chord sampling.
    /// Plenty for pen-pace timing — the schedule needs proportionality, not
    /// micrometers.
    public func approximateLength(curveSamples: Int = 8) -> CGFloat {
        var length: CGFloat = 0
        var current = CGPoint.zero
        var subpathStart = CGPoint.zero

        applyWithBlock { pointer in
            let element = pointer.pointee
            switch element.type {
            case .moveToPoint:
                current = element.points[0]
                subpathStart = current
            case .addLineToPoint:
                let p = element.points[0]
                length += current.distance(to: p)
                current = p
            case .addQuadCurveToPoint:
                let control = element.points[0]
                let end = element.points[1]
                var previous = current
                for step in 1...curveSamples {
                    let t = CGFloat(step) / CGFloat(curveSamples)
                    let point = CGPoint.quadPoint(t: t, from: current, control: control, to: end)
                    length += previous.distance(to: point)
                    previous = point
                }
                current = end
            case .addCurveToPoint:
                let c1 = element.points[0]
                let c2 = element.points[1]
                let end = element.points[2]
                var previous = current
                for step in 1...curveSamples {
                    let t = CGFloat(step) / CGFloat(curveSamples)
                    let point = CGPoint.cubicPoint(t: t, from: current, c1: c1, c2: c2, to: end)
                    length += previous.distance(to: point)
                    previous = point
                }
                current = end
            case .closeSubpath:
                length += current.distance(to: subpathStart)
                current = subpathStart
            @unknown default:
                break
            }
        }
        return length
    }
}

private extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat {
        hypot(other.x - x, other.y - y)
    }

    static func quadPoint(t: CGFloat, from p0: CGPoint, control c: CGPoint, to p1: CGPoint) -> CGPoint {
        let mt = 1 - t
        return CGPoint(
            x: mt * mt * p0.x + 2 * mt * t * c.x + t * t * p1.x,
            y: mt * mt * p0.y + 2 * mt * t * c.y + t * t * p1.y
        )
    }

    static func cubicPoint(t: CGFloat, from p0: CGPoint, c1: CGPoint, c2: CGPoint, to p1: CGPoint) -> CGPoint {
        let mt = 1 - t
        let a = mt * mt * mt
        let b = 3 * mt * mt * t
        let c = 3 * mt * t * t
        let d = t * t * t
        return CGPoint(
            x: a * p0.x + b * c1.x + c * c2.x + d * p1.x,
            y: a * p0.y + b * c1.y + c * c2.y + d * p1.y
        )
    }
}
