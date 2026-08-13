import SwiftUI

// Shared diegetic components: wax seals, candle flames, vials, gold
// toggles, the room's nav bar. All sized for ≥44pt targets.

private struct ReduceInkMotionKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// In-app "reduce motion" (Drawer toggle) OR'd with the system setting
    /// at the injection site.
    var reduceInkMotion: Bool {
        get { self[ReduceInkMotionKey.self] }
        set { self[ReduceInkMotionKey.self] = newValue }
    }
}

/// The room's one reduce-motion gate. The ink is the product: under the
/// setting a reveal still *arrives*, it simply stops travelling — a short
/// crossfade in place of a spring, never a cut to nothing. Ambient motion
/// (flames, pulses, the shelf's breathing glow) has no reduced form and is
/// the one thing that does stop.
enum InkMotion {
    /// The reduced stand-in: long enough to read as a change, short enough
    /// to carry no motion.
    static let calm = Animation.easeOut(duration: 0.2)

    static func gated(_ animation: Animation, reduce: Bool) -> Animation {
        reduce ? calm : animation
    }

    /// Repeating/ambient decoration — nil under the setting, so the implicit
    /// `.animation(_:value:)` simply snaps.
    static func ambient(_ animation: Animation, reduce: Bool) -> Animation? {
        reduce ? nil : animation
    }

    /// Travelling transitions (slide, scale, spring-in) collapse to a plain
    /// crossfade; the content still appears.
    static func arrival(_ transition: AnyTransition, reduce: Bool) -> AnyTransition {
        reduce ? .opacity : transition
    }

    // MARK: - The page surface (the one gesture the product speaks)

    /// **Ink goes down, the answer comes up — one move, two directions.**
    ///
    /// The whole concept is disappearing and appearing: the page drinks what
    /// you wrote and hands something back through the same surface. So the
    /// sink and the rise are not two animations that happen to look alike;
    /// they are one spec run forwards and backwards, defined here once and
    /// read by everything that crosses the paper — the canvas ink, the ink
    /// reply, the developed picture, the moving picture.
    ///
    /// The numbers are the contract in CLAUDE.md ("Inkwoven Ink Behaviour"):
    /// the absorb runs 1500ms to blur 7 and 7pt of sink, on one shared
    /// curve. Under Reduce Motion every beat folds to about a third and
    /// nothing skips.
    enum Surface {
        /// How long the ink takes to go under, and the answer to come up.
        static let travel: Double = 1.5
        /// Reduce Motion keeps the arrival, drops most of the journey:
        /// the contract's fold (×0.35).
        static let calmTravel: Double = 0.525
        /// How far a thing drifts as it crosses the paper. Down for ink
        /// going under, up for an answer surfacing — same distance, so the
        /// two read as the same depth of page.
        static let depth: CGFloat = 7
        /// Out-of-focus at the moment of crossing: paper is not glass.
        static let haze: CGFloat = 7

        /// Going under: the page drinking. Slow to start, gone by the end —
        /// the contract's cubic-bezier(.55,.06,.68,.19).
        static func sink(reduce: Bool) -> Animation {
            .timingCurve(0.55, 0.06, 0.68, 0.19, duration: reduce ? calmTravel : travel)
        }

        /// Coming up: the answer surfacing. The exact inverse — same
        /// distance, same haze, the curve mirrored.
        static func rise(reduce: Bool) -> Animation {
            .timingCurve(0.32, 0.81, 0.45, 0.94, duration: reduce ? calmTravel : travel)
        }
    }

    // MARK: - The darkroom (the develop contract)

    /// The remaining CLAUDE.md contract beats that are not the surface
    /// crossing: the develop, and the reduced-motion fold every timed beat
    /// obeys.
    enum Script {
        /// A picture develops over this, veil to clear.
        static let develop: Double = 2.2

        /// The contract's reduced-motion fold: every time folds to about a
        /// third, floored where a beat would stop reading as one. Nothing
        /// skips.
        static func folded(_ seconds: Double, reduce: Bool) -> Double {
            reduce ? max(0.09, seconds * 0.35) : seconds
        }
    }
}

/// The rise, as a transition — for content that is inserted rather than
/// toggled (the ink reply, the develop frame). Enters from `depth` below,
/// hazy and absent, and arrives sharp: the same crossing `Surface.sink`
/// performs in the other direction.
private struct SurfaceCrossing: ViewModifier {
    var submerged: Bool

    func body(content: Content) -> some View {
        content
            .opacity(submerged ? 0 : 1)
            .blur(radius: submerged ? InkMotion.Surface.haze : 0)
            .offset(y: submerged ? InkMotion.Surface.depth : 0)
    }
}

extension AnyTransition {
    @MainActor static let inkSurface = AnyTransition.modifier(
        active: SurfaceCrossing(submerged: true),
        identity: SurfaceCrossing(submerged: false)
    )
}

extension View {
    /// `.animation(_:value:)` with the reduce-motion gate applied.
    func inkAnimation<V: Equatable>(
        _ animation: Animation, value: V, reduce: Bool
    ) -> some View {
        self.animation(InkMotion.gated(animation, reduce: reduce), value: value)
    }
}

struct PressScaleStyle: ButtonStyle {
    var scale: CGFloat = 0.97

    func makeBody(configuration: Configuration) -> some View {
        Pressed(configuration: configuration, scale: scale)
    }

    /// A ButtonStyle is not a View, so its own `@Environment` properties are
    /// never updated — the reduce-motion read has to happen inside a real
    /// view in the hierarchy.
    private struct Pressed: View {
        let configuration: ButtonStyleConfiguration
        let scale: CGFloat
        @Environment(\.reduceInkMotion) private var reduceMotion

        var body: some View {
            configuration.label
                // Under reduce motion the press still answers — it dims
                // rather than shrinks, so the affordance survives.
                .scaleEffect(configuration.isPressed && !reduceMotion ? scale : 1)
                .opacity(configuration.isPressed && reduceMotion ? 0.72 : 1)
                .animation(.easeOut(duration: 0.18), value: configuration.isPressed)
        }
    }
}

// MARK: - Wax seal

struct WaxSeal: View {
    var diameter: CGFloat = 50

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(hex: 0x9A4340), Ink.wax, Ink.waxDeep],
                        center: UnitPoint(x: 0.38, y: 0.32),
                        startRadius: 0,
                        endRadius: diameter * 0.72
                    )
                )
                .shadow(color: .black.opacity(0.35), radius: 5, y: 3)
            Circle()
                .stroke(Color.white.opacity(0.18), lineWidth: 1.5)
                .blur(radius: 1)
                .offset(y: 1)
                .clipShape(Circle())
            Text("❦")
                .font(InkFont.display(diameter * 0.54))
                .foregroundStyle(Ink.sealIvory)
                // Ornament in the wax — VoiceOver spoke "floral heart"
                // before every seal CTA's label (audit A-7).
                .accessibilityHidden(true)
        }
        .frame(width: diameter, height: diameter)
    }
}

/// Seal + italic caption, the recurring commit affordance.
struct WaxSealButton: View {
    let label: String
    var diameter: CGFloat = 50
    var labelFont: Font = InkFont.bodyItalic(16)
    var labelColor: Color = Ink.wax
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 13) {
                WaxSeal(diameter: diameter)
                Text(label)
                    .font(labelFont)
                    .foregroundStyle(labelColor)
            }
            .padding(6)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle(scale: 0.94))
    }
}

// MARK: - Candle

struct CandleFlame: View {
    var width: CGFloat = 9
    @Environment(\.reduceInkMotion) private var reduceMotion
    @State private var phase = false

    var body: some View {
        Ellipse()
            .fill(
                RadialGradient(
                    colors: [Color(hex: 0xFFF3D0), Ink.candleBright, Ink.candle, .clear],
                    center: UnitPoint(x: 0.5, y: 0.65),
                    startRadius: 0,
                    endRadius: width * 1.4
                )
            )
            .frame(width: width, height: width * 1.8)
            .shadow(color: Ink.candleBright.opacity(0.5), radius: width * 1.2)
            .opacity(reduceMotion ? 0.9 : (phase ? 1 : 0.82))
            .scaleEffect(reduceMotion ? 1 : (phase ? 1.05 : 1), anchor: .bottom)
            // repeatForever must start in an explicit transaction: flipping
            // the flag in onAppear lands in the first render pass, so an
            // implicit .animation(value:) never sees a change to animate
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                    phase = true
                }
            }
    }
}

struct CandleStub: View {
    var height: CGFloat = 44
    var dimmed = false

    var body: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 4)
                .fill(
                    LinearGradient(
                        colors: dimmed
                            ? [Color(hex: 0xD9C69A), Color(hex: 0xB7A377)]
                            : [Ink.parchment, Color(hex: 0xD9C69A)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .frame(width: height * 0.27, height: height * 0.68)
            if dimmed {
                Circle()
                    .fill(Ink.inkFaded)
                    .frame(width: 7, height: 9)
                    .offset(y: -height * 0.62)
            } else {
                CandleFlame(width: height * 0.2)
                    .offset(y: -height * 0.6)
            }
        }
        .frame(height: height, alignment: .bottom)
    }
}

// MARK: - Vial

/// Wax-sealed vial of moving-picture credit.
struct VialView: View {
    var width: CGFloat = 22
    var height: CGFloat = 46
    var fill: CGFloat = 0.55

    var body: some View {
        ZStack(alignment: .bottom) {
            UnevenRoundedRectangle(
                topLeadingRadius: 4, bottomLeadingRadius: 7,
                bottomTrailingRadius: 7, topTrailingRadius: 4
            )
            .fill(LinearGradient(colors: [Color(hex: 0x2A2016), Color(hex: 0x150E08)], startPoint: .top, endPoint: .bottom))
            .overlay(
                UnevenRoundedRectangle(
                    topLeadingRadius: 4, bottomLeadingRadius: 7,
                    bottomTrailingRadius: 7, topTrailingRadius: 4
                )
                .stroke(Ink.wax, lineWidth: 1.5)
            )
            .overlay(alignment: .top) {
                // wax stopper
                Capsule()
                    .fill(Ink.candle.opacity(0.4))
                    .frame(height: 4)
                    .padding(.horizontal, 2)
                    .padding(.top, 2)
            }
            RoundedRectangle(cornerRadius: 3)
                .fill(LinearGradient(colors: [Ink.candleBright, Ink.candle, Ink.wax], startPoint: .top, endPoint: .bottom))
                .frame(height: max(0, (height - 8) * fill))
                .padding([.horizontal, .bottom], 3)
        }
        .frame(width: width, height: height)
    }
}

// MARK: - Lock

struct LockGlyph: View {
    var color: Color = Ink.candle
    var bodyColor: LinearGradient = LinearGradient(
        colors: [Ink.candleBright, Ink.candle], startPoint: .top, endPoint: .bottom
    )
    @Environment(\.reduceInkMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        VStack(spacing: -2) {
            UnevenRoundedRectangle(
                topLeadingRadius: 8, bottomLeadingRadius: 0,
                bottomTrailingRadius: 0, topTrailingRadius: 8
            )
            .stroke(color, lineWidth: 2.5)
            .frame(width: 11, height: 9)
            RoundedRectangle(cornerRadius: 3)
                .fill(bodyColor)
                .frame(width: 16, height: 11)
        }
        .opacity(reduceMotion ? 0.6 : (pulse ? 0.8 : 0.35))
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

// MARK: - Room nav bar

/// Sticky candlelit bar with a back pill and centered small-caps title.
struct RoomNavBar: View {
    let title: String
    var backLabel = "the shelf"
    let onBack: () -> Void
    @Environment(\.room) private var room

    var body: some View {
        ZStack {
            SmallCapsLabel(text: title, size: 12.5, tracking: 2.5, color: room.dim)
            HStack {
                Button(action: onBack) {
                    HStack(spacing: 6) {
                        Text("‹").font(InkFont.body(15))
                            .accessibilityHidden(true) // ornament (audit A-7)
                        SmallCapsLabel(text: backLabel, size: 11.5, tracking: 1.4, color: room.accent)
                    }
                    .foregroundStyle(room.accent)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 38)
                    .background(
                        Capsule()
                            .fill(room.accent.opacity(0.08))
                            .overlay(Capsule().stroke(room.accent.opacity(0.28), lineWidth: 1))
                    )
                    // The pill stays 38pt tall to the eye; the target does
                    // not (audit M-16).
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressScaleStyle())
                Spacer()
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 13)
        .background(room.bar)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Rectangle().fill(room.accent.opacity(0.14)).frame(height: 1)
        }
    }
}

// MARK: - Gold toggle

struct GoldToggle: View {
    let isOn: Bool
    let action: () -> Void
    @Environment(\.room) private var room
    @Environment(\.reduceInkMotion) private var reduceMotion

    var body: some View {
        Button {
            action()
            // After, not before: the tick reports the state the toggle now
            // holds — switching haptics off ends in silence, on with a tick.
            Feel.shared.tick()
        } label: {
            Capsule()
                .fill(isOn ? Ink.candle : Color(hex: 0x785A28, opacity: 0.24))
                .overlay(
                    Capsule().stroke(
                        isOn ? Ink.candle : Color(hex: 0x785A28, opacity: 0.45),
                        lineWidth: 1
                    )
                )
                .overlay(alignment: isOn ? .trailing : .leading) {
                    Circle()
                        .fill(isOn ? Color(hex: 0xFFFDF5) : Color(hex: 0xCBB488))
                        .padding(2)
                        .shadow(color: .black.opacity(0.4), radius: 1.5, y: 1)
                }
                .frame(width: 50, height: 29)
                // The knob crosses the capsule on an alignment change — real
                // translation, so it takes the gate.
                .inkAnimation(.easeOut(duration: 0.18), value: isOn, reduce: reduceMotion)
                // 44pt target INSIDE the label with the shape declared after
                // the frame (audit M-15): declared outside the Button, the
                // frame only spaced the layout and the real target stayed the
                // 50×29 capsule.
                .frame(minWidth: 50, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(isOn ? "on" : "off")
    }
}

// MARK: - Segmented pills

struct SegmentedPills<T: Hashable>: View {
    let options: [(label: String, value: T)]
    let selection: T
    let choose: (T) -> Void
    @Environment(\.room) private var room

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.value) { opt in
                let selected = opt.value == selection
                Button {
                    if !selected { Feel.shared.tick() }
                    choose(opt.value)
                } label: {
                    Text(opt.label)
                        .font(selected ? InkFont.bodySemiBold(13) : InkFont.body(13))
                        .foregroundStyle(selected ? Color(hex: 0x241A10) : room.text)
                        .padding(.horizontal, 15)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(selected ? Ink.candle : .clear))
                        // Each segment answers to the full 44pt (audit M-16);
                        // the outer capsule keeps its height because its own
                        // vertical padding gave the difference back below.
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 3)
        .background(
            Capsule()
                .fill(Color(hex: 0x785A28, opacity: 0.14))
                .overlay(Capsule().stroke(room.accent.opacity(0.2), lineWidth: 1))
        )
    }
}

// MARK: - Settle bounce

/// **Off.** Whether the page shows anything at all during its rest window —
/// the settle bounce and the cancel-send button, the only two things that
/// ever spoke while the writer paused.
///
/// The room is an enchanted object, not an interface: ink goes under, an
/// answer comes up, and a writer learns that beat in one page. Chrome that
/// counts down to the send taught nothing the disappearance doesn't teach
/// better, and at a 2s window it fired on every pause between words.
///
/// Left as a switch, not a deletion: `SettleBounce` still builds, and one
/// `true` here brings both affordances back. The flyleaf signature keeps its
/// captioned bounce either way — that page teaches the mechanic on purpose.
enum RestWindowAffordances {
    static let shown = false
}

/// "Take your time" — three ink droplets bobbing in a slow stagger while the
/// page waits out a pause in the writing. The bounce is the promise: nothing
/// sends while the dots still dance. Used wherever a rest window is open
/// (the flyleaf signature; the page's idle-send when `RestWindowAffordances`
/// is switched back on).
struct SettleBounce: View {
    var color: Color = Ink.inkFaded
    var caption: String?
    var dot: CGFloat = 5
    @Environment(\.reduceInkMotion) private var reduceMotion
    @State private var up = false

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(color.opacity(0.75))
                        .frame(width: dot, height: dot)
                        .offset(y: up ? -4.5 : 1.5)
                        .animation(
                            reduceMotion ? nil : .easeInOut(duration: 0.62)
                                .repeatForever(autoreverses: true)
                                .delay(Double(index) * 0.15),
                            value: up
                        )
                }
            }
            .padding(.bottom, 2)
            if let caption {
                Text(caption)
                    .font(InkFont.bodyItalic(14.5))
                    .foregroundStyle(Ink.inkFaded)
            }
        }
        // .task, not .onAppear: the flag must flip after the first render
        // pass or the implicit .animation(value:) never sees a change
        // (same trap as CandleFlame).
        .task {
            guard !reduceMotion else { return }
            up = true
        }
        // Three bobbing dots say nothing out loud; the promise they carry is
        // the whole mechanic, so it has to be spoken.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(caption ?? "The page waits — nothing sends while the ink is still settling.")
    }
}

// MARK: - Quiet banner

/// In-fiction status marginalia (offline, cooldown, "the page waits"):
/// italic, ink-faded, never red. Rendered in the page's TOP margin — the
/// writing hand owns the bottom (occlusion rule, task B6).
struct QuietBanner: View {
    let text: String
    var size: CGFloat = 15

    var body: some View {
        Text(text)
            .font(InkFont.bodyItalic(size))
            .foregroundStyle(Ink.inkFaded)
            .lineSpacing(3)
    }
}

// MARK: - Shapes

/// Bookmark ribbon with a notched tail.
struct RibbonShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: .zero)
            p.addLine(to: CGPoint(x: rect.maxX, y: 0))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY * 0.84))
            p.addLine(to: CGPoint(x: 0, y: rect.maxY))
            p.closeSubpath()
        }
    }
}

struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: 0, y: rect.midY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        }
    }
}


// MARK: - Room card

struct RoomCard<Content: View>: View {
    var borderOpacity: Double = 0.14
    @ViewBuilder let content: Content
    @Environment(\.room) private var room

    var body: some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(LinearGradient(colors: [room.cardTop, room.cardBottom], startPoint: .top, endPoint: .bottom))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(room.accent.opacity(borderOpacity), lineWidth: 1)
                    )
            )
    }
}
