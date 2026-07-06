import Foundation
import CoreGraphics
import CoreText

// @unchecked: CGPath lacks a Sendable annotation, but the paths stored here
// come from CTFontCreatePathForGlyph and are immutable.
public struct GlyphPath: @unchecked Sendable {
    public var path: CGPath
    public var position: CGPoint
    public var length: CGFloat
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

            let runFont: CTFont
            if let attrs = CTRunGetAttributes(run) as? [String: Any],
               let f = attrs[kCTFontAttributeName as String] {
                runFont = (f as! CTFont)
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
