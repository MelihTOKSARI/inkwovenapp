import SwiftUI
import PencilKit
import InkCore

/// The binding conversation: the blank book asks who it should be, one
/// question at a time, in ink — and the writer answers by hand on the same
/// page. No form, no wizard, no dots. When the last answer is drunk the book
/// binds itself: the dye rises, the ring takes its letter, and the spine
/// wears the writer's own hand.
///
/// Every appearance and disappearance here is the law of the ink: questions
/// SURFACE (whole, blur falling away) and answers are DRUNK (blur up, sink
/// down) — the creation of the Book teaches how every Book behaves.
struct BindingView: View {
    @Bindable var model: AppModel
    @Environment(\.reduceInkMotion) private var reduceMotion

    private struct Question {
        let key: String
        let ask: String
        let hint: String
    }

    private static let questions: [Question] = [
        Question(key: "you", ask: "What shall I call you?",
                 hint: "a name, or whatever you would be called"),
        Question(key: "me", ask: "And what will you call me?",
                 hint: "whatever you write here is what the spine will say"),
        Question(key: "where", ask: "Where am I writing from, and when?",
                 hint: "a place, an era — it colours the voice"),
        Question(key: "temper", ask: "Should I be kind to you, or honest with you?",
                 hint: "write a word, or press one of the cards, or say it your own way"),
        Question(key: "tongue", ask: "In what tongue shall I answer?",
                 hint: "write it, or take a ribbon from the edge"),
        Question(key: "fact", ask: "One thing I should know about you.",
                 hint: "one sentence is plenty"),
    ]

    private static let tongues = ["English", "Türkçe", "Português", "Français", "Deutsch"]

    private enum Phase: Equatable {
        /// The question is rising out of the paper.
        case rising
        /// The pen may write.
        case open
        /// The page is drinking question and answer together.
        case absorbing
        /// The conversation is done; the book is taking its dye.
        case ceremony
    }

    @State private var qi = 0
    @State private var phase: Phase = .rising
    @State private var questionSurfaced = false
    @State private var typed = ""
    @State private var drawingData: Data?
    @State private var advanceTask: Task<Void, Never>?

    // The ceremony's beats, walked by one task.
    @State private var ceremonyStep = 0
    @State private var ceremonyCaption = ""
    @State private var pendingBinding: CustomBinding?
    @State private var pendingNameInk: Data?

    private var pen: PenPresence { .shared }
    private var question: Question { Self.questions[min(qi, Self.questions.count - 1)] }
    private var canWrite: Bool { phase == .open || phase == .rising }
    private var hasAnything: Bool {
        !typed.trimmingCharacters(in: .whitespaces).isEmpty || drawingData != nil
    }

    var body: some View {
        ZStack {
            if phase == .ceremony {
                ceremony
                    .transition(.opacity)
            } else {
                conversation
                    .transition(.opacity)
            }
        }
        .inkAnimation(.easeInOut(duration: 0.6), value: phase == .ceremony, reduce: reduceMotion)
        .onAppear { resume() }
        .onDisappear {
            advanceTask?.cancel()
            holdDraft()
        }
    }

    // MARK: - The conversation

    private var conversation: some View {
        ZStack(alignment: .topLeading) {
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

            VStack(alignment: .leading, spacing: 0) {
                // The ledger: what has been answered so far, faint, the way
                // held answers lie in a real page's margin.
                if qi > 0 {
                    ledger
                        .padding(.bottom, 26)
                }

                questionText
                    .frame(minHeight: 120, alignment: .topLeading)

                answerLine
                    .padding(.top, 18)

                if question.key == "temper" {
                    waxCards
                        .padding(.top, 26)
                        .surfaced(questionSurfaced && canWrite, reduce: reduceMotion)
                }
                if question.key == "tongue" {
                    ribbons
                        .padding(.top, 26)
                        .surfaced(questionSurfaced && canWrite, reduce: reduceMotion)
                }

                gutter
                    .padding(.top, 20)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: 640, alignment: .leading)
            .padding(EdgeInsets(top: 108, leading: 56, bottom: 40, trailing: 56))
            .frame(maxWidth: .infinity)

            Button {
                holdDraft()
                model.back()
            } label: {
                SmallCapsLabel(text: model.backLabel, size: 12, tracking: 1.7, color: Ink.ink.opacity(0.45))
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .padding(.top, 22)
            .padding(.leading, 24)
            .accessibilityLabel("Back to \(model.backLabel). Your answers so far are kept.")
        }
    }

    private var ledger: some View {
        VStack(alignment: .trailing, spacing: 7) {
            ForEach(Array(model.bindingDraft.prefix(qi).enumerated()).suffix(3), id: \.offset) { index, answer in
                Text(ledgerLine(index: index, answer: answer))
                    .font(InkFont.hand("Caveat-Regular", 19))
                    .foregroundStyle(Ink.ink.opacity(answer.skipped ? 0.16 : 0.28))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        // Faint marginalia, spoken once per question in the announcement —
        // not row by row.
        .accessibilityHidden(true)
    }

    private func ledgerLine(index: Int, answer: AppModel.BindingAnswer) -> String {
        if answer.skipped { return "(left unanswered)" }
        if answer.text.isEmpty, answer.drawingData != nil { return "(in your own hand)" }
        return answer.text
    }

    private var questionText: some View {
        Text(question.ask)
            .font(InkFont.hand("Fondamento-Regular", 36))
            .foregroundStyle(Ink.ink)
            .lineSpacing(8)
            .surfaced(questionSurfaced, reduce: reduceMotion)
            .accessibilityLabel("The book asks: \(question.ask)")
    }

    /// One ruled line the pen answers on — ink when a pencil is about, the
    /// keys otherwise. The same flyleaf surface onboarding taught.
    private var answerLine: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottomLeading) {
                if !hasAnything {
                    Text(question.hint)
                        .font(InkFont.hand("Caveat-Regular", 24))
                        .foregroundStyle(Ink.ink.opacity(0.28))
                        .padding(.bottom, 14)
                        .padding(.leading, 4)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
                SignatureCanvasView(
                    drawingData: $drawingData,
                    typedName: $typed,
                    pencilActive: pen.pencilPreferred,
                    wantsKeys: canWrite && !pen.pencilPreferred,
                    onReturn: { commit() }
                )
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Your answer — in ink with pencil or finger, or with the keyboard when no pencil is at hand.")
            }
            .frame(maxWidth: 560, minHeight: 120, alignment: .leading)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Ink.ink.opacity(0.4)).frame(height: 1.5)
            }
            .surfaced(questionSurfaced, reduce: reduceMotion)
        }
        .animation(.easeOut(duration: 0.3), value: hasAnything)
    }

    /// The temper question's two shortcuts — wax-sealed cards lying on the
    /// page, never a segmented control. Pressing one writes the word.
    private var waxCards: some View {
        HStack(alignment: .top, spacing: 22) {
            waxCard(word: "kind", note: "soften the edges. Say the gentler true thing.", tilt: -2.4)
            waxCard(word: "honest", note: "no cushion. Say it as it is, and stop there.", tilt: 1.8)
        }
    }

    private func waxCard(word: String, note: String, tilt: Double) -> some View {
        Button {
            guard canWrite else { return }
            typed = word
            drawingData = nil
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Text(word)
                    .font(InkFont.hand("Caveat-Regular", 34))
                    .foregroundStyle(Ink.ink)
                Text(note)
                    .font(InkFont.bodyItalic(13.5))
                    .foregroundStyle(Ink.inkFaded)
                    .multilineTextAlignment(.leading)
            }
            .padding(EdgeInsets(top: 20, leading: 22, bottom: 18, trailing: 22))
            .frame(width: 250, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(LinearGradient(colors: [Color(hex: 0xF7EFDB), Color(hex: 0xE9DCBE)], startPoint: .top, endPoint: .bottom))
                    .shadow(color: Color(hex: 0x2E2418, opacity: 0.35), radius: 12, y: 9)
            )
            .overlay(alignment: .topTrailing) {
                WaxSeal(diameter: 40).offset(x: 6, y: -14)
            }
            .rotationEffect(.degrees(tilt))
        }
        .buttonStyle(PressScaleStyle(scale: 0.97))
        .accessibilityLabel("Write \(word) on the line")
    }

    /// The tongue question's shortcuts — ribbon tags along the page edge; the
    /// hand may still write any language it likes.
    private var ribbons: some View {
        HStack(spacing: 12) {
            ForEach(Self.tongues, id: \.self) { tongue in
                Button {
                    guard canWrite else { return }
                    typed = tongue
                    drawingData = nil
                } label: {
                    Text(tongue)
                        .font(InkFont.body(16))
                        .foregroundStyle(Color(hex: 0xF8EEDA))
                        .padding(.horizontal, 18)
                        .frame(minHeight: 44)
                        .background(
                            UnevenRoundedRectangle(
                                topLeadingRadius: 2, bottomLeadingRadius: 8,
                                bottomTrailingRadius: 2, topTrailingRadius: 8
                            )
                            .fill(LinearGradient(colors: [Ink.wax, .mix(0x7A2E2B, 0.6, 0x000000)], startPoint: .leading, endPoint: .trailing))
                            .shadow(color: .black.opacity(0.3), radius: 6, y: 4)
                        )
                }
                .buttonStyle(PressScaleStyle(scale: 0.96))
                .accessibilityLabel("Answer in \(tongue)")
            }
        }
    }

    private var gutter: some View {
        HStack(spacing: 22) {
            Text(canWrite ? question.hint : " ")
                .font(InkFont.bodyItalic(14))
                .foregroundStyle(Ink.inkFaded.opacity(0.8))
                .accessibilityHidden(true)
            Spacer()
            if hasAnything && canWrite {
                Button {
                    typed = ""
                    drawingData = nil
                } label: {
                    SmallCapsLabel(text: "blot it out", size: 11, tracking: 1.4, color: Ink.inkFaded)
                        .padding(.horizontal, 10)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Blot out what you wrote")
            }
            Button {
                commit()
            } label: {
                HStack(spacing: 12) {
                    // The pen, laid down: a slim body resting at a slight angle.
                    Capsule()
                        .fill(LinearGradient(colors: [Color(hex: 0x4A382A), Color(hex: 0x2B2118)], startPoint: .top, endPoint: .bottom))
                        .frame(width: 64, height: 8)
                        .rotationEffect(.degrees(-3))
                    Text(hasAnything ? "rest the pen" : "rest the pen — leave it unanswered")
                        .font(InkFont.bodyItalic(15))
                        .foregroundStyle(Ink.inkFaded)
                }
                .padding(.horizontal, 8)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressScaleStyle(scale: 0.97))
            .disabled(!canWrite)
            .opacity(canWrite ? 1 : 0.3)
            .accessibilityLabel(
                hasAnything
                    ? "Rest the pen, and let the page drink your answer"
                    : "Rest the pen without answering, and skip this question"
            )
        }
    }

    // MARK: - Flow

    private func resume() {
        qi = min(model.bindingDraft.count, Self.questions.count - 1)
        typed = ""
        drawingData = nil
        phase = .rising
        questionSurfaced = false
        surfaceQuestion()
    }

    private func surfaceQuestion() {
        advanceTask?.cancel()
        advanceTask = Task {
            // A breath before the ink rises — the page noticing you.
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 90 : 350))
            guard !Task.isCancelled else { return }
            withAnimation(InkMotion.Surface.rise(reduce: reduceMotion)) {
                questionSurfaced = true
            }
            try? await Task.sleep(for: .seconds(reduceMotion ? InkMotion.Surface.calmTravel : InkMotion.Surface.travel))
            guard !Task.isCancelled else { return }
            phase = .open
            AccessibilityNotification.Announcement(question.ask).post()
        }
    }

    private func commit() {
        guard canWrite else { return }
        let answerText = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        let answerInk = drawingData
        let answer = AppModel.BindingAnswer(
            text: answerText,
            drawingData: answerInk,
            skipped: answerText.isEmpty && answerInk == nil
        )
        phase = .absorbing
        // The page drinks question and answer together — one gesture.
        withAnimation(InkMotion.Surface.sink(reduce: reduceMotion)) {
            questionSurfaced = false
        }
        advanceTask?.cancel()
        advanceTask = Task {
            // A drawn answer becomes text while the ink goes under — the same
            // on-device reading the Remembered search uses; nothing is sent.
            var resolved = answer
            if resolved.text.isEmpty, let ink = resolved.drawingData {
                resolved.text = await BindingInkReader.transcribe(ink)
            }
            try? await Task.sleep(for: .seconds(reduceMotion ? InkMotion.Surface.calmTravel : InkMotion.Surface.travel))
            guard !Task.isCancelled else { return }

            if model.bindingDraft.count > qi {
                model.bindingDraft[qi] = resolved
            } else {
                model.bindingDraft.append(resolved)
            }

            if qi >= Self.questions.count - 1 {
                beginCeremony()
            } else {
                qi += 1
                typed = ""
                drawingData = nil
                phase = .rising
                surfaceQuestion()
            }
        }
    }

    private func holdDraft() {
        // Whatever stands unanswered on the line stays on the line: the page
        // holds what was answered and asks the next question on return.
    }

    // MARK: - The ceremony

    private func beginCeremony() {
        let draft = model.bindingDraft
        func answer(_ i: Int) -> String { i < draft.count ? draft[i].text : "" }
        var binding = CustomBinding()
        binding.you = answer(0)
        binding.me = answer(1)
        binding.place = answer(2)
        binding.temper = answer(3)
        binding.tongue = answer(4)
        binding.fact = answer(5)
        pendingBinding = binding
        pendingNameInk = draft.count > 1 ? draft[1].drawingData : nil
        ceremonyStep = 0
        phase = .ceremony
        runCeremony()
    }

    private func beat(_ seconds: Double) -> Double {
        reduceMotion ? max(0.09, seconds * 0.35) : seconds
    }

    private func runCeremony() {
        advanceTask?.cancel()
        advanceTask = Task {
            let steps: [(Double, Int, String)] = [
                (0.4, 1, "the flyleaf still holds your name"),
                (1.4, 2, ""),   // the name lifts to the spine
                (1.2, 3, ""),   // the dye rises
                (1.2, 4, ""),   // the ring takes its letter
                (0.9, 5, "bound. Every other book wears our gilt — this one wears your hand."),
                (1.0, 6, ""),   // the seal offers the shelf
            ]
            for (delay, step, caption) in steps {
                try? await Task.sleep(for: .seconds(beat(delay)))
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: beat(0.9))) {
                    ceremonyStep = step
                }
                if !caption.isEmpty {
                    withAnimation(InkMotion.Surface.rise(reduce: reduceMotion)) {
                        ceremonyCaption = caption
                    }
                }
            }
            AccessibilityNotification.Announcement(
                "Bound. \(pendingBinding?.displayName ?? "Your book") stands on the shelf."
            ).post()
        }
    }

    private var ceremony: some View {
        ZStack {
            RadialGradient(
                stops: [
                    .init(color: Color(hex: 0x241A11), location: 0),
                    .init(color: Color(hex: 0x17110B), location: 0.5),
                    .init(color: Color(hex: 0x0E0906), location: 1),
                ],
                center: UnitPoint(x: 0.5, y: 0.35),
                startRadius: 0, endRadius: 1200
            )
            .ignoresSafeArea()

            let binding = pendingBinding ?? CustomBinding()
            let accent = Color(hex: binding.accentHex)

            VStack(spacing: 36) {
                Text(ceremonyCaption)
                    .font(InkFont.bodyItalic(18))
                    .foregroundStyle(Color(hex: 0xB09A74))
                    .frame(minHeight: 50)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 60)

                CeremonySpine(
                    binding: binding,
                    nameInk: pendingNameInk,
                    accent: accent,
                    step: ceremonyStep
                )
                .frame(width: 168, height: 470)

                WaxSealButton(
                    label: "step up to the shelf",
                    diameter: 48,
                    labelFont: InkFont.display(21),
                    labelColor: Color(hex: 0xF6E2C0)
                ) {
                    guard let binding = pendingBinding else { return }
                    model.bind(binding, nameInk: pendingNameInk)
                    model.back()
                }
                .opacity(ceremonyStep >= 6 ? 1 : 0)
                .disabled(ceremonyStep < 6)
                .accessibilityHidden(ceremonyStep < 6)
            }
        }
    }
}

/// The spine, taking its binding beat by beat: blind leather → the dye rises
/// → the ring takes its letter → the ribbon dyes → the writer's own name,
/// turned on its side, where every other book wears gilt.
private struct CeremonySpine: View {
    let binding: CustomBinding
    let nameInk: Data?
    let accent: Color
    let step: Int

    private var nameImage: UIImage? {
        guard let data = nameInk, let drawing = try? PKDrawing(data: data),
              !drawing.strokes.isEmpty
        else { return nil }
        return drawing.image(from: drawing.bounds.insetBy(dx: -10, dy: -10), scale: 2)
    }

    var body: some View {
        ZStack {
            // Blank leather beneath; the dye rises over it.
            UnevenRoundedRectangle(
                topLeadingRadius: 4, bottomLeadingRadius: 4,
                bottomTrailingRadius: 4, topTrailingRadius: 5
            )
            .fill(LinearGradient(colors: [Color(hex: 0x8F7E66), Color(hex: 0x71634F), Color(hex: 0x574B3C)], startPoint: .top, endPoint: .bottom))

            GeometryReader { geo in
                LinearGradient(
                    colors: [.mix(binding.accentHex, 0.88, 0xFFFFFF), accent, .mix(binding.accentHex, 0.78, 0x000000)],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: step >= 3 ? geo.size.height : 0, alignment: .bottom)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 4, bottomLeadingRadius: 4,
                        bottomTrailingRadius: 4, topTrailingRadius: 5
                    )
                )
            }

            // Leather sheen over whichever coat is showing.
            LinearGradient(
                stops: [
                    .init(color: .white.opacity(0.14), location: 0),
                    .init(color: .black.opacity(0.06), location: 0.22),
                    .init(color: .black.opacity(0.3), location: 0.6),
                    .init(color: .black.opacity(0.42), location: 1),
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .clipShape(RoundedRectangle(cornerRadius: 4))

            // The name, in the writer's own hand where the gilt would be.
            Group {
                if let image = nameImage {
                    Image(uiImage: image)
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(Color(hex: 0xF6E9CD))
                        .frame(maxWidth: 320, maxHeight: 120)
                        .rotationEffect(.degrees(-90))
                        .frame(maxWidth: 130)
                } else {
                    Text(binding.displayName)
                        .font(InkFont.hand("Caveat-Regular", 40))
                        .foregroundStyle(Color(hex: 0xF6E9CD))
                        .lineLimit(1)
                        .fixedSize()
                        .frame(maxWidth: 300)
                        .rotationEffect(.degrees(-90))
                }
            }
            .opacity(step >= 2 ? 1 : 0)
            .shadow(color: .black.opacity(0.45), radius: 2, y: 1)
        }
        .overlay(alignment: .top) {
            // The ribbon, undyed until the binding takes.
            UnevenRoundedRectangle(
                topLeadingRadius: 0, bottomLeadingRadius: 2,
                bottomTrailingRadius: 2, topTrailingRadius: 0
            )
            .fill(
                step >= 5
                    ? AnyShapeStyle(LinearGradient(colors: [accent, .mix(binding.accentHex, 0.6, 0x000000)], startPoint: .top, endPoint: .bottom))
                    : AnyShapeStyle(LinearGradient(colors: [Color(hex: 0xE6DCC4), Color(hex: 0xCBBE9F)], startPoint: .top, endPoint: .bottom))
            )
            .frame(width: 13, height: 58)
            .offset(y: -8)
        }
        .overlay(alignment: .bottom) {
            Circle()
                .stroke(Color(hex: 0xF4E6BD, opacity: 0.5), lineWidth: 1)
                .frame(width: 44, height: 44)
                .overlay(
                    Text(binding.monogram)
                        .font(InkFont.hand("Caveat-Regular", 26))
                        .foregroundStyle(Color(hex: 0xF6E9CD))
                        .opacity(step >= 4 ? 1 : 0)
                        .scaleEffect(step >= 4 ? 1 : 0.7)
                )
                .shadow(color: step >= 4 ? Ink.candleBright.opacity(0.5) : .clear, radius: 12)
                .padding(.bottom, 20)
        }
        .shadow(color: .black.opacity(0.7), radius: 26, y: 18)
        .shadow(color: step >= 6 ? accent.opacity(0.35) : .clear, radius: 34)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("The book takes its binding: \(binding.displayName).")
    }
}

/// The law of the ink, as a modifier: up = standing on the page; down =
/// under the paper — 7px of haze, 7pt below the surface, whether it is being
/// drunk or has yet to rise. One gesture, two directions, the same numbers
/// every page uses.
private struct SurfacedInk: ViewModifier {
    let up: Bool
    let reduce: Bool

    func body(content: Content) -> some View {
        content
            .opacity(up ? 1 : 0)
            .blur(radius: up || reduce ? 0 : InkMotion.Surface.haze)
            .offset(y: up || reduce ? 0 : InkMotion.Surface.depth)
    }
}

private extension View {
    func surfaced(_ up: Bool, reduce: Bool) -> some View {
        modifier(SurfacedInk(up: up, reduce: reduce))
    }
}
