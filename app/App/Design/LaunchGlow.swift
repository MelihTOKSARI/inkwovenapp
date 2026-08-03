import SwiftUI

/// The candle is lit before the room appears.
///
/// A cold launch lands on the system launch screen — a flat pane of
/// `LaunchBackground` — and this veil picks up from that exact tone so the
/// handoff between the two is invisible. Then a candle blooms out of the dark,
/// the wordmark writes itself in left to right, and the whole thing crossfades
/// to whichever screen the model chose.
///
/// **A splash is a gift the first time and a toll every time after**, and this
/// app wants daily returns — so the whole sequence is budgeted at
/// `Beat.total` (1.35s) and every duration lives in `Beat` where it can be
/// argued with. It shows once per process, never on foreground resume, and
/// steps aside entirely for the `-ink.` launch flows, which need to land on
/// the screen they asked for rather than sit through ceremony.
struct LaunchGlowView: View {
    /// Fired when the veil has finished its part; the parent runs the lift so
    /// the crossfade lands on the live room. `Beat.lift` is that duration.
    var onFinished: () -> Void
    @Environment(\.reduceInkMotion) private var reduceMotion

    @State private var glowing = false
    @State private var written = false

    /// Every duration in the sequence, in one place. The three beats are the
    /// bloom, the writing, and the lift; `total` is what the budget is
    /// actually measured against.
    enum Beat {
        /// The candle catching — light gathering, not a flash.
        static let bloom = 0.55
        /// The name starts before the bloom finishes, so the two read as one
        /// gesture rather than a sequence of two.
        static let writeDelay = 0.20
        static let write = 0.62
        /// A breath on the finished wordmark before the room takes over.
        static let hold = 0.23
        /// The crossfade out, run by the parent.
        static let lift = 0.30

        /// Reduce Motion: nothing travels. The name simply arrives, holds, and
        /// the veil lifts — and it is over sooner, because the thing being
        /// waited through has been removed.
        static let reducedFade = 0.22
        static let reducedHold = 0.26
        static let reducedLift = 0.24

        /// First frame to veil gone. Budget 1.4s, hard cap 1.6s.
        static let total = writeDelay + write + hold + lift        // 1.35s
        static let reducedTotal = reducedFade + reducedHold + reducedLift // 0.72s
    }

    /// Cold launch only, and never under the review/UITest/handoff launch
    /// args — those flows measure and photograph the screen they asked for.
    ///
    /// Not `#if DEBUG`-gated: the store-screenshot and UITest runs are the
    /// whole reason this exists, and a check that quietly stops applying in
    /// some configuration is a check nobody can rely on.
    ///
    /// `nonisolated` because `RootView` reads it in a stored-property
    /// initializer: conformance to the MainActor-isolated `View` protocol
    /// infers isolation onto this type, and only ProcessInfo is read here.
    nonisolated static var shouldShow: Bool {
        !ProcessInfo.processInfo.arguments.contains { $0.hasPrefix("-ink.") }
    }

    var body: some View {
        ZStack {
            // Flat first frame, byte-identical to the `LaunchBackground`
            // colorset the system launch screen uses. Any step or flash here
            // is the one thing that would give the whole effect away.
            Color(hex: 0x17110B).ignoresSafeArea()

            // The bloom: candlelight gathering in the middle of the dark.
            // Scaling up AS it fades in, so the light appears to grow rather
            // than to switch on.
            RadialGradient(
                colors: [
                    Ink.candleBright.opacity(0.30),
                    Ink.candle.opacity(0.10),
                    .clear,
                ],
                center: .center,
                startRadius: 0,
                endRadius: 430
            )
            .scaleEffect(glowing ? 1.0 : 0.55)
            .opacity(glowing ? 1 : 0)
            .ignoresSafeArea()
            // Under Reduce Motion there is no bloom at all — the wordmark
            // carries the whole moment.
            .opacity(reduceMotion ? 0 : 1)

            wordmark
        }
        // Hidden from VoiceOver entirely: the real first screen owns focus
        // from the start, and a decorative veil must never delay or steal it.
        .accessibilityHidden(true)
        .task { await run() }
    }

    private var wordmark: some View {
        Text("Inkwoven")
            .font(InkFont.display(42))
            .foregroundStyle(
                LinearGradient(
                    colors: [RoomTheme.candlelight.logoFrom, RoomTheme.candlelight.logoTo],
                    startPoint: .top, endPoint: .bottom
                )
            )
            // Reduce Motion fades the finished name in; everyone else gets it
            // written. The mask below is the mechanism in the normal case, so
            // opacity stays at 1 there — a wordmark that fades AND sweeps
            // reads as a block appearing, which is what the sweep exists to
            // avoid.
            .opacity(reduceMotion ? (written ? 1 : 0) : 1)
            .mask(alignment: .leading) { sweep }
    }

    /// A feathered band travelling across the glyphs so the name resolves left
    /// to right, the way a nib would lay it down. The band is moved by offset
    /// rather than by animating gradient stops, which keeps it smooth.
    @ViewBuilder
    private var sweep: some View {
        if reduceMotion {
            Rectangle()
        } else {
            GeometryReader { geo in
                let band = geo.size.width * 1.7
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: 0.7),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .leading, endPoint: .trailing
                )
                .frame(width: band)
                .offset(x: written ? 0 : -band)
            }
        }
    }

    private func run() async {
        if reduceMotion {
            withAnimation(.easeOut(duration: Beat.reducedFade)) { written = true }
            try? await Task.sleep(for: .seconds(Beat.reducedFade + Beat.reducedHold))
        } else {
            withAnimation(.easeOut(duration: Beat.bloom)) { glowing = true }
            try? await Task.sleep(for: .seconds(Beat.writeDelay))
            withAnimation(.easeInOut(duration: Beat.write)) { written = true }
            try? await Task.sleep(for: .seconds(Beat.write + Beat.hold))
        }
        onFinished()
    }
}

#Preview("Launch glow") {
    LaunchGlowView(onFinished: {})
}
