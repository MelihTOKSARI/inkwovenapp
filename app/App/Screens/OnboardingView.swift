import SwiftUI
import PencilKit

/// The notebook introduces itself in ink, asks your name, and gifts one
/// sealed vial. AI disclosure is woven into the fiction and restated
/// plainly at the foot.
///
/// Signing is pen-first with a settle window: ink (or keys) never commits on
/// the instant — the page bounces softly while you finish your hand, and only
/// seals after the writing has rested. When no pencil is about (simulator, an
/// iPad without one), the keyboard rises as the fallback hand.
struct OnboardingView: View {
    @Bindable var model: AppModel
    @Environment(\.reduceInkMotion) private var reduceMotion
    @State private var shownCharacters = 0
    @State private var streamTask: Task<Void, Never>?

    /// Signature accepted — the vial and seal have bounced onto the page.
    @State private var sealed = false
    /// A settle window is open: the bounce dances, nothing commits yet.
    @State private var settling = false
    /// The ink was no more than a drop — ask for a fuller hand.
    @State private var slightInk = false
    @State private var typedName = ""
    @State private var settleTask: Task<Void, Never>?

    private var pen: PenPresence { .shared }

    private static let intro = "I am a notebook, and tonight I become yours. What appears on these pages is drawn by a spirit of ink — not a person, not a friend, but a hand that answers when yours moves. Tell me true things, and I will answer in kind. First, though — sign your name below, in your own hand."

    private var streamed: Bool { shownCharacters >= Self.intro.count }
    private var hasInk: Bool { model.signatureData != nil }

    /// Ink settles slower than keys: a signature has flourishes.
    private var settleWindow: Duration {
        .milliseconds(reduceMotion ? 900 : 2200)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            RadialGradient(
                stops: [
                    .init(color: Ink.parchmentBright, location: 0),
                    .init(color: Ink.parchment, location: 0.46),
                    .init(color: Ink.parchmentDeep, location: 1),
                ],
                center: UnitPoint(x: 0.3, y: 0),
                startRadius: 0,
                endRadius: 1300
            )
            .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    SmallCapsLabel(text: "Inkwoven", size: 13, tracking: 3.9, color: Ink.inkFaded)
                        .padding(.bottom, 24)

                    // AI disclosure as top-margin marginalia (occlusion rule:
                    // the writing hand owns the bottom of the page) — plain
                    // truth, worn like a bookplate.
                    disclosure
                        .padding(.bottom, 40)

                    intro
                        .frame(minHeight: 220, alignment: .topLeading)

                    if streamed {
                        signature
                            .padding(.top, 40)
                            .transition(InkMotion.arrival(
                                .opacity.combined(with: .move(edge: .bottom)), reduce: reduceMotion
                            ))
                    }

                    if sealed {
                        giftedVial
                            .padding(.top, 34)
                            .transition(InkMotion.arrival(sealArrival, reduce: reduceMotion))

                        WaxSealButton(
                            label: "step up to the shelf",
                            diameter: 52,
                            labelFont: InkFont.display(22)
                        ) {
                            model.finishOnboarding()
                        }
                        .padding(.top, 48)
                        .transition(InkMotion.arrival(sealArrival, reduce: reduceMotion))
                    }
                }
                .frame(maxWidth: 640, alignment: .leading)
                .padding(EdgeInsets(top: 92, leading: 56, bottom: 60, trailing: 56))
                .frame(maxWidth: .infinity)
            }

            Button {
                model.finishOnboarding()
            } label: {
                SmallCapsLabel(text: "skip", size: 12, tracking: 1.7, color: Ink.ink.opacity(0.4))
                    .padding(.horizontal, 12)
                    .frame(minHeight: 40)
            }
            .padding(.top, 22)
            .padding(.trailing, 24)
        }
        .onAppear {
            // A returning signer walks in already sealed.
            sealed = model.signatureData != nil || !model.signedName.isEmpty
            stream()
        }
        .onDisappear {
            streamTask?.cancel()
            settleTask?.cancel()
        }
        .onChange(of: model.signatureData) { _, data in
            inkChanged(data)
        }
        .onChange(of: typedName) { _, name in
            guard !sealed else { return }
            settleTask?.cancel()
            guard !name.trimmingCharacters(in: .whitespaces).isEmpty else {
                withAnimation(.easeOut(duration: 0.3)) { settling = false }
                return
            }
            armSettle { commitTyped() }
        }
    }

    /// Every prefix of the intro, built once. `String.prefix(_:)` walks
    /// graphemes from the start and allocates a fresh String, and it ran
    /// inside the body on every one of the 289 stream ticks.
    private static let introPrefixes: [String] = {
        var out = [""]
        var accumulated = ""
        for character in intro {
            accumulated.append(character)
            out.append(accumulated)
        }
        return out
    }()

    private var intro: some View {
        (Text(Self.introPrefixes[min(shownCharacters, Self.introPrefixes.count - 1)])
            + (streamed ? Text("") : Text(" ▌").foregroundStyle(Ink.ink.opacity(0.6))))
            .font(InkFont.displayItalic(28))
            .foregroundStyle(Ink.ink)
            .lineSpacing(14)
            // VoiceOver must never be handed a half-written sentence — the
            // stream is a flourish, the disclosure inside it is not.
            .accessibilityLabel(Self.intro)
    }

    /// The flyleaf: pen-first (task H1). Ink is the honored hand; when no
    /// pencil has ever touched the glass, the keys stand in beneath the line.
    private var signature: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                SmallCapsLabel(text: "sign, and it is yours", size: 12, tracking: 2.2, color: Ink.inkFaded)
                Spacer(minLength: 12)
                if sealed || hasInk {
                    Button {
                        beginAgain()
                    } label: {
                        SmallCapsLabel(text: "begin again", size: 10.5, tracking: 1.3, color: Ink.inkFaded)
                            .padding(.horizontal, 10)
                            .frame(minHeight: 34)
                    }
                    .buttonStyle(PressScaleStyle())
                    .transition(.opacity)
                }
            }
            .frame(maxWidth: 380)

            ZStack(alignment: .bottomLeading) {
                if !hasInk && typedName.isEmpty && !sealed {
                    Text(pen.pencilPreferred ? "sign your name in ink" : "sign your name — the keys will write for you")
                        .font(InkFont.hand("Caveat-Regular", 25))
                        .foregroundStyle(Ink.ink.opacity(0.3))
                        .padding(.bottom, 14)
                        .padding(.leading, 4)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
                // ONE field, two hands: ink when the pen is about, the
                // keyboard's script otherwise — never two inputs.
                SignatureCanvasView(
                    drawingData: $model.signatureData,
                    typedName: $typedName,
                    pencilActive: pen.pencilPreferred,
                    wantsKeys: streamed && !pen.pencilPreferred && !sealed,
                    onReturn: {
                        settleTask?.cancel()
                        commitTyped()
                    }
                )
                // `.contain`, never the bare form: the no-argument default
                // ignores children and hid the keys fallback outright, so a
                // VoiceOver user with no pencil could not sign at all — and
                // signing is the only way past this screen but "skip".
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("signature-canvas")
                .accessibilityLabel("The flyleaf. Sign your name — in ink with pencil or finger, or with the keyboard when no pencil is at hand.")
            }
            .frame(maxWidth: 380, minHeight: 110, alignment: .leading)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Ink.ink.opacity(0.42)).frame(height: 1.5)
            }

            if settling {
                SettleBounce(caption: "the ink settles — take your time")
                    .padding(.top, 10)
                    .transition(.opacity)
            }

            if slightInk {
                QuietBanner(text: "A drop is not a name — write it in full, and the page will know you.", size: 14)
                    .padding(.top, 10)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.35), value: settling)
        .animation(.easeOut(duration: 0.35), value: slightInk)
        .animation(.easeOut(duration: 0.5), value: sealed)
        .animation(.easeOut(duration: 0.5), value: hasInk)
    }

    // MARK: - Settle & seal

    private func inkChanged(_ data: Data?) {
        guard !sealed else { return }
        settleTask?.cancel()
        guard data != nil else {
            withAnimation(.easeOut(duration: 0.3)) { settling = false }
            return
        }
        withAnimation(.easeOut(duration: 0.3)) { slightInk = false }
        armSettle { commitInk() }
    }

    /// Opens (or re-opens) the settle window: the bounce shows, and the
    /// commit only fires if the hand truly rests for the whole window.
    private func armSettle(_ commit: @escaping @MainActor () -> Void) {
        settleTask?.cancel()
        withAnimation(.easeIn(duration: 0.3)) { settling = true }
        settleTask = Task {
            try? await Task.sleep(for: settleWindow)
            guard !Task.isCancelled else { return }
            commit()
        }
    }

    private func commitInk() {
        guard let data = model.signatureData, let drawing = try? PKDrawing(data: data) else {
            withAnimation(.easeOut(duration: 0.3)) { settling = false }
            return
        }
        // A single dot is a tap, not a signature — ask for a fuller hand.
        guard max(drawing.bounds.width, drawing.bounds.height) >= 30 else {
            withAnimation(.easeOut(duration: 0.35)) {
                settling = false
                slightInk = true
            }
            return
        }
        seal()
    }

    private func commitTyped() {
        let name = typedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            withAnimation(.easeOut(duration: 0.3)) { settling = false }
            return
        }
        model.signedName = name
        seal()
    }

    /// The vial and the shelf door bounce onto the page together.
    private var sealArrival: AnyTransition {
        .scale(scale: 0.88, anchor: .topLeading).combined(with: .opacity)
    }

    private func seal() {
        // A bouncing scale-in is exactly what the setting exists to suppress,
        // so the seal lands rather than springs — but it still lands.
        withAnimation(InkMotion.gated(
            .spring(response: 0.55, dampingFraction: 0.62), reduce: reduceMotion
        )) {
            settling = false
            slightInk = false
            sealed = true
        }
        // Sealing is the whole gate on this screen and it happens on a timer,
        // with no touch to attribute it to — silence here reads as a dead end.
        AccessibilityNotification.Announcement(
            "Signed. A first moving-picture credit is gifted; the shelf is open."
        ).post()
    }

    private func beginAgain() {
        settleTask?.cancel()
        withAnimation(.easeOut(duration: 0.4)) {
            model.signatureData = nil
            model.signedName = ""
            typedName = ""
            sealed = false
            settling = false
            slightInk = false
        }
    }

    private var giftedVial: some View {
        HStack(spacing: 16) {
            VialView(width: 26, height: 42, fill: 0.55)
            VStack(alignment: .leading, spacing: 2) {
                Text("A first moving-picture credit, gifted.")
                    .font(InkFont.body(17))
                    .foregroundStyle(Ink.ink)
                Text("One sealed vial — spend it when a page asks to move.")
                    .font(InkFont.bodyItalic(14))
                    .foregroundStyle(Color(hex: 0x7A6A4D))
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Ink.wax.opacity(0.055))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Ink.wax.opacity(0.16), lineWidth: 1))
        )
    }

    /// The AI disclosure, worn as a bookplate in the page's top margin —
    /// restated plainly inside the fiction, never buried at the foot.
    private var disclosure: some View {
        HStack(alignment: .top, spacing: 14) {
            CandleStub(height: 40, dimmed: true)
                .opacity(0.7)
            VStack(alignment: .leading, spacing: 5) {
                SmallCapsLabel(text: "a spirit of ink, not a person", size: 11.5, tracking: 2, color: Ink.inkFaded)
                Text("Inkwoven composes fiction on your behalf — it is not advice, and never a substitute for a human hand when you need one.")
                    .font(InkFont.bodyItalic(14.5))
                    .foregroundStyle(Ink.inkFaded)
                    .lineSpacing(4)
            }
        }
        .padding(EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 18))
        .frame(maxWidth: 520, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Ink.ink.opacity(0.035))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Ink.ink.opacity(0.2), lineWidth: 1)
                )
        )
    }

    private func stream() {
        if reduceMotion {
            shownCharacters = Self.intro.count
            return
        }
        shownCharacters = 0
        streamTask = Task {
            while shownCharacters < Self.intro.count, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(26))
                withAnimation(.linear(duration: 0.02)) { shownCharacters += 1 }
            }
            withAnimation(.easeOut(duration: 0.6)) {
                shownCharacters = Self.intro.count
            }
        }
    }
}
