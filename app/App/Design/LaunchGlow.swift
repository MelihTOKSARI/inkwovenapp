import SwiftUI

/// The candle is lit before the room appears. A cold launch lands on the
/// system launch screen — a flat pane of the room's dark (`LaunchBackground`,
/// the same 0x17110B as `Ink.room`) — and this veil picks up from that exact
/// tone: a candle glow blooms out of the dark, the wordmark writes itself in,
/// and the whole thing lifts to reveal whichever screen the model chose.
///
/// It shows once per process, never on foreground-resume, and steps aside for
/// the review/UITest launch args so `-ink.startScreen` flows still land on a
/// clean first frame. Under reduce-motion the wordmark simply arrives — a
/// fade, no bloom, no travel — and the veil lifts sooner.
struct LaunchGlowView: View {
    /// Fired once, after the hold; the parent owns the fade-out so the
    /// crossfade into the live room uses the parent's transition.
    var onFinished: () -> Void
    @Environment(\.reduceInkMotion) private var reduceMotion

    @State private var glowing = false
    @State private var written = false
    @State private var finished = false

    /// Cold launch only, and never under the handoff/UITest launch args —
    /// those flows measure and photograph the screen they asked for, not a
    /// second and a half of ceremony in front of it.
    ///
    /// `nonisolated` because `RootView` reads it in a stored-property
    /// initializer: conformance to the MainActor-isolated `View` protocol
    /// infers isolation onto this type, and only ProcessInfo is read here.
    nonisolated static var shouldShow: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("-ink.") }) {
            return false
        }
        #endif
        return true
    }

    var body: some View {
        ZStack {
            // Flat first frame, identical to the system launch screen — the
            // handoff between the two must be invisible.
            Color(hex: 0x17110B).ignoresSafeArea()

            // The bloom: candlelight gathering in the middle of the dark.
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

            wordmark
        }
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
            .blur(radius: written || reduceMotion ? 0 : 4)
            .opacity(written ? 1 : (reduceMotion ? 0 : 0.35))
            .mask(alignment: .leading) {
                // The ink-write: a feathered band sweeps across the glyphs so
                // the name resolves left to right, the way a nib would lay it
                // down. Offset (not gradient stops) so it animates everywhere.
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
                    .offset(x: written || reduceMotion ? 0 : -band)
                }
            }
    }

    private func run() async {
        if reduceMotion {
            // The reduced form: the name arrives, holds, and the veil lifts.
            withAnimation(.easeOut(duration: 0.25)) { written = true }
            try? await Task.sleep(for: .milliseconds(750))
        } else {
            withAnimation(.easeOut(duration: 0.85)) { glowing = true }
            try? await Task.sleep(for: .milliseconds(280))
            withAnimation(.easeInOut(duration: 0.9)) { written = true }
            try? await Task.sleep(for: .milliseconds(1250))
        }
        guard !finished else { return }
        finished = true
        onFinished()
    }
}

#Preview("Launch glow") {
    LaunchGlowView(onFinished: {})
}
