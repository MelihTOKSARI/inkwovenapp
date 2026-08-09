import SwiftUI

/// **The thing on the other side of the paper, breathing.**
///
/// Between the ink going under and the answer coming up there is a stretch of
/// blank page. That emptiness read as a dead page rather than a thinking one —
/// so something stirs down there while the Book composes.
///
/// This is deliberately NOT a status indicator, and the difference is the whole
/// design. A spinner says *the app is busy*; this says *the thing you wrote to
/// is alive*. It communicates no progress, has no determinate form, sits below
/// the threshold where you could point at its outline, and would be a worse
/// spinner than any spinner. That is the point.
///
/// **Fixed silhouette, moving life.** The bloom's shape is hand-authored and
/// identical every exchange — a random shape per page would make the diary a
/// different creature each time, and would ship an outline nobody had ever
/// looked at. The variation lives in the motion instead: three lobes of the
/// same bloom, each at its own scale, rotation and phase, pulsing on periods
/// that do not divide into each other. The composite never repeats inside a
/// wait, and never stops being the same organism.
struct QuickeningBloom: View {
    /// Fades the whole thing in and out; the page owns the timing so the
    /// bloom can clear ahead of the reply's rise.
    var present: Bool
    @Environment(\.reduceInkMotion) private var reduceMotion

    /// Mounted for as long as there is something to show, including the fade
    /// out — the removal transition holds the view alive until it has finished
    /// leaving, and nothing ticks on an idle page. This replaces pausing the
    /// timeline in place: a schedule that has to be un-paused to come back is
    /// one more thing between the wait and the only thing that fills it.
    @State private var showing = false

    /// The three lobes. Periods are mutually indivisible (1.1 / 1.7 / 2.6), so
    /// the composite breath drifts instead of ticking — the ear for this is
    /// the same one that hears a metronome behind a bad loading animation.
    /// 1.1s leads because it is a resting heart, and just off the page's own
    /// 1s crossing, so the bloom reads as a separate living thing rather than
    /// the interface keeping time with itself.
    private static let lobes: [Lobe] = [
        Lobe(scale: 1.00, rotation: .degrees(0), period: 1.10, swell: 0.070, density: 1.00),
        Lobe(scale: 0.82, rotation: .degrees(137), period: 1.70, swell: 0.090, density: 0.72),
        Lobe(scale: 1.18, rotation: .degrees(251), period: 2.60, swell: 0.055, density: 0.46),
    ]

    /// The frozen instant the still bloom is drawn at, chosen because the three
    /// lobes are at visibly different points of their beat there — a still
    /// drawn at t=0 has every lobe at the same phase and reads as a stencil.
    private static let stillMoment: Double = 0.5

    struct Lobe {
        let scale: CGFloat
        let rotation: Angle
        /// Seconds for one full lub-dub.
        let period: Double
        /// How far the lobe swells, as a fraction of its own size.
        let swell: CGFloat
        /// How much ink this lobe carries, against the darkest one.
        let density: Double
    }

    var body: some View {
        ZStack {
            if showing {
                bloom.transition(.opacity)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { show(present) }
        .onChange(of: present) { _, isPresent in show(isPresent) }
    }

    /// The page owns the fade so the bloom is gone before the answer arrives in
    /// the same space.
    private func show(_ wanted: Bool) {
        guard showing != wanted else { return }
        withAnimation(wanted ? .easeIn(duration: 0.55) : .easeOut(duration: 0.4)) {
            showing = wanted
        }
    }

    @ViewBuilder
    private var bloom: some View {
        // Reduce Motion stops the *motion*, not the presence. Taking the whole
        // bloom away left those readers with the dead page this exists to
        // answer — so the same ink sits there, still, and fades in and out.
        if reduceMotion {
            stain(at: Self.stillMoment)
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                stain(at: timeline.date.timeIntervalSinceReferenceDate)
            }
        }
    }

    private func stain(at t: Double) -> some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            // The bloom is drawn well beyond its visible extent and then
            // blurred past legibility — the softness has to come from real
            // overspill, not from a faded edge, or it reads as a shape with a
            // border.
            let base = min(size.width, size.height) * 0.31

            context.addFilter(.blur(radius: base * 0.34))
            context.blendMode = .multiply

            for lobe in Self.lobes {
                let beat = Self.heartbeat(t / lobe.period)
                let radius = base * lobe.scale * (1 + lobe.swell * beat)
                // Density is what carries the pulse. A radius that swells a few
                // percent behind a 30-odd point blur moves an edge nobody can
                // find; ink that gets darker and lighter is the thing you see
                // out of the corner of your eye, which is the only way this is
                // ever seen.
                let charge = 1 + 0.50 * beat
                // A slow wander: the bloom is never quite where it was, which
                // is what keeps a long wait from reading as a frozen stain.
                let drift = CGSize(
                    width: base * 0.080 * sin(t / 4.7 + lobe.period),
                    height: base * 0.065 * cos(t / 6.3 + lobe.period)
                )
                var path = InkBloom.path(
                    in: CGRect(
                        x: center.x - radius + drift.width,
                        y: center.y - radius + drift.height,
                        width: radius * 2,
                        height: radius * 2
                    )
                )
                path = path.applying(
                    CGAffineTransform(translationX: center.x, y: center.y)
                        .rotated(by: lobe.rotation.radians)
                        .translatedBy(x: -center.x, y: -center.y)
                )
                // Ink in water, not a lit shape: densest off-centre so there is
                // no bullseye for the eye to lock onto, and gone to nothing well
                // inside the path's own edge. The three lobes multiply into each
                // other, so the core settles near 17% ink at rest — a watermark
                // you can feel on the paper. The first pass sat at 5%, which is
                // less contrast than the paper's own vignette carries across the
                // same span: it was drawing the whole time, into nothing.
                let ink = lobe.density * charge
                context.fill(
                    path,
                    with: .radialGradient(
                        Gradient(stops: [
                            .init(color: Ink.ink.opacity(0.088 * ink), location: 0.00),
                            .init(color: Ink.ink.opacity(0.068 * ink), location: 0.42),
                            .init(color: Ink.ink.opacity(0.024 * ink), location: 0.74),
                            .init(color: .clear, location: 1.00),
                        ]),
                        center: CGPoint(
                            x: center.x - radius * 0.16,
                            y: center.y - radius * 0.22
                        ),
                        startRadius: 0,
                        endRadius: radius * 1.05
                    )
                )
            }
        }
    }

    /// One lub-dub, normalized to a 0–1 cycle and returned in −1…1.
    ///
    /// A sine would be a breath; a heart is two beats and a long fall. The
    /// second beat is smaller than the first and follows close behind it, then
    /// nothing for over half the cycle — that silence is what makes the shape
    /// read as a pulse rather than a pump.
    private static func heartbeat(_ cycle: Double) -> CGFloat {
        let phase = cycle - cycle.rounded(.down)
        func thump(at center: Double, width: Double, height: Double) -> Double {
            let d = (phase - center) / width
            return height * exp(-d * d * 4)
        }
        let lub = thump(at: 0.06, width: 0.11, height: 1.00)
        let dub = thump(at: 0.26, width: 0.13, height: 0.62)
        // Rests just below zero between beats: the bloom draws in a little
        // before it swells, the way something breathing does.
        return CGFloat(lub + dub - 0.18)
    }
}

/// The silhouette itself — hand-authored, asymmetric, and identical on every
/// page the bloom ever draws.
///
/// No circle, no ring, no arc: the moment a reader can find a centre or a
/// radius it stops being ink and starts being a progress element. The control
/// points below are tuned so no two lobes of the outline match and no axis is
/// a mirror, while the whole still closes smoothly enough to blur into a
/// single mass.
enum InkBloom {
    static func path(in rect: CGRect) -> Path {
        // Authored in a unit square and scaled, so the shape is resolution-
        // independent and the numbers stay readable.
        let unit: [(point: CGPoint, control1: CGPoint, control2: CGPoint)] = [
            (CGPoint(x: 0.50, y: 0.02), CGPoint(x: 0.72, y: 0.00), CGPoint(x: 0.86, y: 0.13)),
            (CGPoint(x: 0.93, y: 0.34), CGPoint(x: 0.99, y: 0.46), CGPoint(x: 0.95, y: 0.55)),
            (CGPoint(x: 0.81, y: 0.72), CGPoint(x: 0.91, y: 0.84), CGPoint(x: 0.78, y: 0.90)),
            (CGPoint(x: 0.55, y: 0.97), CGPoint(x: 0.66, y: 1.01), CGPoint(x: 0.40, y: 1.02)),
            (CGPoint(x: 0.22, y: 0.86), CGPoint(x: 0.10, y: 0.93), CGPoint(x: 0.04, y: 0.77)),
            (CGPoint(x: 0.09, y: 0.48), CGPoint(x: 0.00, y: 0.62), CGPoint(x: 0.01, y: 0.33)),
            (CGPoint(x: 0.50, y: 0.02), CGPoint(x: 0.16, y: 0.10), CGPoint(x: 0.31, y: 0.03)),
        ]

        func place(_ p: CGPoint) -> CGPoint {
            CGPoint(x: rect.minX + p.x * rect.width, y: rect.minY + p.y * rect.height)
        }

        var path = Path()
        path.move(to: place(unit[unit.count - 1].point))
        for segment in unit {
            path.addCurve(
                to: place(segment.point),
                control1: place(segment.control1),
                control2: place(segment.control2)
            )
        }
        path.closeSubpath()
        return path
    }
}
