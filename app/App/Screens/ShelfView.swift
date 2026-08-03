import SwiftUI

/// Home: the candlelit shelf of eight hands.
struct ShelfView: View {
    @Bindable var model: AppModel
    @Environment(\.room) private var room
    @Environment(\.reduceInkMotion) private var reduceMotion
    @State private var glowPulse = false
    /// Drives the vial's breathing glow and the highlight travelling its glass.
    @State private var vialGlow = false

    var body: some View {
        GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height
            ZStack {
                candleGlow(size: geo.size)
                vignette

                shelfArea(size: geo.size, landscape: landscape)

                RiddleDiaryLine()
                    .frame(maxWidth: min(640, geo.size.width * 0.84))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, landscape ? 118 : 182)
                    .allowsHitTesting(false)

                VStack {
                    header
                    Spacer()
                    caption
                        .padding(.bottom, landscape ? 24 : 40)
                }

                if model.visibleBooks.isEmpty {
                    emptyShelfNote
                }
            }
        }
    }

    // MARK: - Room dressing

    private func candleGlow(size: CGSize) -> some View {
        RadialGradient(
            colors: [Ink.candleBright.opacity(0.16), Ink.candle.opacity(0.05), .clear],
            center: UnitPoint(x: 0.3, y: 0.3),
            startRadius: 0,
            endRadius: size.width * 0.32
        )
        .frame(width: size.width * 0.46, height: size.height * 0.7)
        .blur(radius: 6)
        .scaleEffect(reduceMotion ? 1 : (glowPulse ? 1.08 : 1))
        .opacity(reduceMotion ? 0.6 : (glowPulse ? 0.72 : 0.45))
        .position(x: size.width * 0.31, y: size.height * 0.21)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 3.5).repeatForever(autoreverses: true)) {
                glowPulse = true
            }
        }
        .allowsHitTesting(false)
    }

    private var vignette: some View {
        RadialGradient(
            colors: [.clear, .clear, room.vignette],
            center: UnitPoint(x: 0.5, y: 0.42),
            startRadius: 0,
            endRadius: 900
        )
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            HStack(spacing: 16) {
                CandleStub(height: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Inkwoven")
                        .font(InkFont.display(30))
                        .foregroundStyle(
                            LinearGradient(colors: [room.logoFrom, room.logoTo], startPoint: .top, endPoint: .bottom)
                        )
                    Text("a candlelit shelf of eight hands")
                        .font(InkFont.bodyItalic(13))
                        .foregroundStyle(room.logoSub)
                }
            }
            Spacer()
            HStack(spacing: 12) {
                // The Vials are back on the shelf: the modality they fund works
                // end to end (Epic J), so the shop has something to sell. It
                // sits first because it is the only door here that leads to the
                // hero feature.
                roomButton(label: "Vials", destination: .wallet) { vialsIcon }
                roomButton(label: "Bindery", destination: .bindery) { binderyDoorIcon }
                roomButton(label: "Drawer", destination: .drawer) { drawerIcon }
            }
        }
        .padding(.top, 26)
        .padding(.horizontal, 34)
    }

    private func roomButton(
        label: String, destination: AppScreen, @ViewBuilder icon: () -> some View
    ) -> some View {
        Button {
            // No haptic: opening a room is navigation, and navigation is not
            // an event the hand needs told about.
            // The shop remembers it was opened from the shelf, so closing it
            // comes back here rather than to whatever room opened it last.
            if destination == .wallet {
                model.openVials(from: .shelf)
            } else {
                model.go(destination)
            }
        } label: {
            VStack(spacing: 5) {
                icon().frame(height: 40, alignment: .bottom)
                SmallCapsLabel(text: label, size: 10, tracking: 1.4, color: room.dim)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(minWidth: 46, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
    }

    /// The vial on the shelf, catching the candle. The glow breathes and a
    /// highlight slides down the glass — slow enough to read as a lit object in
    /// the room rather than a badge demanding attention. Reduce Motion keeps
    /// the vial and a steady glow, simply held still.
    private var vialsIcon: some View {
        VialView(width: 22, height: 38, fill: 0.62)
            .shadow(
                color: Ink.candle.opacity(reduceMotion ? 0.35 : (vialGlow ? 0.6 : 0.22)),
                radius: vialGlow ? 9 : 5
            )
            .overlay {
                if !reduceMotion {
                    // A single band of light travelling the length of the glass.
                    LinearGradient(
                        colors: [.clear, Ink.candleBright.opacity(0.5), .clear],
                        startPoint: .top, endPoint: .bottom
                    )
                    .frame(height: 14)
                    .blur(radius: 3)
                    .offset(y: vialGlow ? 17 : -17)
                    .mask(VialView(width: 22, height: 38, fill: 1))
                    .allowsHitTesting(false)
                }
            }
            .frame(width: 30, height: 40)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) {
                    vialGlow = true
                }
            }
    }

    private var binderyDoorIcon: some View {
        UnevenRoundedRectangle(
            topLeadingRadius: 15, bottomLeadingRadius: 3,
            bottomTrailingRadius: 3, topTrailingRadius: 15
        )
        .fill(LinearGradient(colors: [Color(hex: 0x3A2A1A), Color(hex: 0x1D140C)], startPoint: .top, endPoint: .bottom))
        .overlay(
            UnevenRoundedRectangle(
                topLeadingRadius: 15, bottomLeadingRadius: 3,
                bottomTrailingRadius: 3, topTrailingRadius: 15
            )
            .stroke(Color(hex: 0x55401F), lineWidth: 1.5)
        )
        .overlay(alignment: .trailing) {
            Circle().fill(Ink.candle).frame(width: 4, height: 4).padding(.trailing, 5)
        }
        .frame(width: 30, height: 40)
    }

    private var drawerIcon: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(LinearGradient(colors: [Color(hex: 0x2A2016), Color(hex: 0x181109)], startPoint: .top, endPoint: .bottom))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(hex: 0x4A3A24), lineWidth: 1.5))
            .overlay(
                Circle()
                    .fill(Color(hex: 0x8A7658))
                    .frame(width: 7, height: 7)
                    .background(Circle().fill(Color(hex: 0x8A7658, opacity: 0.18)).frame(width: 13, height: 13))
            )
            .frame(width: 36, height: 22)
    }

    // MARK: - Shelf

    private func shelfArea(size: CGSize, landscape: Bool) -> some View {
        let ledgeBottom: CGFloat = landscape ? 92 : 178
        let rowHeight = min(landscape ? 438 : 560, size.height * 0.55)
        return ZStack(alignment: .bottom) {
            // falling shadow under the ledge
            LinearGradient(colors: [.black.opacity(0.5), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 26)
                .blur(radius: 3)
                .padding(.horizontal, 24)
                .padding(.bottom, ledgeBottom - 22)

            // the books
            HStack(alignment: .bottom, spacing: landscape ? 14 : 12) {
                ForEach(model.visibleBooks) { book in
                    BookSpineView(
                        book: book,
                        focused: model.focusedBookID == book.id,
                        tap: {
                            // Peek is a tick; a cover actually coming open is
                            // the fuller settle. A locked Book routes to the
                            // gate — the unlock has its own moment there.
                            let opens = model.focusedBookID == book.id
                                && (!book.locked || model.keeperUnlocked)
                            Feel.shared.play(opens ? .bookOpen : .tick)
                            model.tap(book: book)
                        },
                        hide: { model.toggleShelf(book: book) }
                    )
                }
            }
            .frame(maxWidth: size.width - 80, maxHeight: rowHeight, alignment: .bottom)
            .padding(.bottom, ledgeBottom + 12)

            // the ledge
            RoundedRectangle(cornerRadius: 3)
                .fill(LinearGradient(colors: [room.ledgeTop, room.ledgeMid, room.ledgeBottom], startPoint: .top, endPoint: .bottom))
                .frame(height: 20)
                .overlay(alignment: .top) {
                    Rectangle().fill(room.accent.opacity(0.14)).frame(height: 1)
                }
                .shadow(color: .black.opacity(0.6), radius: 10, y: 8)
                .padding(.horizontal, 24)
                .padding(.bottom, ledgeBottom)
        }
        .frame(maxHeight: .infinity, alignment: .bottom)
    }

    private var emptyShelfNote: some View {
        (Text("Every book is hidden.\nBring one back in ")
            + Text("the Drawer › Books & Shelf").foregroundStyle(room.accent)
            + Text("."))
            .font(InkFont.bodyItalic(18))
            .foregroundStyle(room.dim)
            .multilineTextAlignment(.center)
            .lineSpacing(5)
    }

    // MARK: - Caption

    @ViewBuilder
    private var caption: some View {
        if let id = model.focusedBookID {
            let book = Book.by(id: id)
            HStack(spacing: 11) {
                Text(book.name)
                    .font(InkFont.display(17))
                    .foregroundStyle(room.heading)
                Text("·").foregroundStyle(room.dim.opacity(0.55))
                Text("tap again to open")
                    .font(InkFont.bodyItalic(14))
                    .foregroundStyle(room.dim)
            }
            .transition(.opacity)
        } else {
            Text(
                model.firstRun
                    ? "The Oracle is awake — tap to peek, tap again to open."
                    : "Tap a book to peek · tap again to open"
            )
            .font(InkFont.bodyItalic(15))
            .foregroundStyle(room.dim)
            .transition(.opacity)
        }
    }
}

// MARK: - The Riddle-diary line

/// Above the books, the notebook talks to itself: a line writes itself out,
/// the page absorbs the ink, and the next hand writes back — the Tom Riddle
/// diary exchange, looping through a short scripted conversation.
struct RiddleDiaryLine: View {
    @Environment(\.room) private var room
    @Environment(\.reduceInkMotion) private var reduceMotion
    @State private var lineIndex = 0
    @State private var shownCount = 0
    @State private var absorbed = true
    @State private var blotPulse = false
    @State private var nibPulse = false

    private enum Hand { case ink, you }
    private struct Line {
        let hand: Hand
        let text: String
        /// Every prefix, built once at construction. `text.prefix(n)` walks
        /// graphemes from the start and allocates a fresh String, and the
        /// body called it every 38ms for as long as the shelf was on screen.
        let prefixes: [String]

        init(hand: Hand, text: String) {
            self.hand = hand
            self.text = text
            var out = [""]
            var accumulated = ""
            for character in text {
                accumulated.append(character)
                out.append(accumulated)
            }
            prefixes = out
        }
    }

    /// The exchange. After the greeting plays once, the loop returns to
    /// index 1 so the salutation isn't repeated.
    ///
    /// `let`, not `var`: as a computed property this rebuilt all seven lines —
    /// a `Calendar.current` lookup and seven string interpolations — on every
    /// body evaluation, i.e. 26 times a second on the home screen.
    private static let lines: [Line] = {
        let hour = Calendar.current.component(.hour, from: .now)
        let part = hour < 5 ? "evening" : hour < 12 ? "morning" : hour < 18 ? "afternoon" : "evening"
        return [
            Line(hand: .ink, text: "Good \(part). This notebook is awake — write, and it writes back."),
            Line(hand: .you, text: "Who are you?"),
            Line(hand: .ink, text: "Eight hands sharing one shelf. Each answers in its own ink."),
            Line(hand: .you, text: "Tell me a story."),
            Line(hand: .ink, text: "Once, a road forked at dusk… the Storyteller keeps the rest for you."),
            Line(hand: .you, text: "Will you keep my secrets?"),
            Line(hand: .ink, text: "The Keeper opens for your hand alone. Nothing leaves these pages."),
        ]
    }()

    var body: some View {
        let lines = Self.lines
        let line = lines[min(lineIndex, lines.count - 1)]
        let writing = !reduceMotion && !absorbed && shownCount > 0 && shownCount < line.text.count

        ZStack(alignment: .bottom) {
            candleBlot
            lineText(line)
                .overlay(alignment: .trailing) {
                    if writing { nibDot.offset(x: 11) }
                }
                .frame(minHeight: 76)
        }
        // the absorb: ink sinks into the page — fade, soften, settle downward.
        // Under reduce motion it only fades: the drift and the shrink are the
        // travelling half, and this loops forever on the home screen.
        .opacity(absorbed ? 0 : 1)
        .blur(radius: absorbed && !reduceMotion ? 5 : 0)
        .offset(y: absorbed && !reduceMotion ? 9 : 0)
        .scaleEffect(absorbed && !reduceMotion ? 0.985 : 1)
        .task { await runExchange(lines) }
        // A decorative loop that talks over everything else is worse than
        // silence; the shelf's own copy already says what this demonstrates.
        .accessibilityHidden(true)
    }

    private func lineText(_ line: Line) -> some View {
        let shown = line.prefixes[min(shownCount, line.prefixes.count - 1)]
        return Group {
            if line.hand == .you {
                Text(shown)
                    .font(InkFont.hand("Caveat-Regular", 26))
                    .foregroundStyle(Color(hex: 0xCDBB97))
            } else {
                Text(shown)
                    .font(InkFont.hand("Tangerine-Bold", 40))
                    .foregroundStyle(room.heading)
                    .shadow(color: Color(hex: 0xE8B84B, opacity: 0.3), radius: 13)
            }
        }
        .multilineTextAlignment(.center)
        .lineSpacing(4)
    }

    /// Faint candle-glow pooling beneath the writing, breathing slowly.
    private var candleBlot: some View {
        Ellipse()
            .fill(
                RadialGradient(
                    stops: [
                        .init(color: Color(hex: 0xE8B84B, opacity: 0.5), location: 0),
                        .init(color: .clear, location: 0.7),
                    ],
                    center: .center, startRadius: 0, endRadius: 95
                )
            )
            .frame(width: 190, height: 34)
            .blur(radius: 10)
            .opacity(blotPulse ? 0.3 : 0.14)
            .scaleEffect(blotPulse ? 1.12 : 1)
            .offset(y: 26)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 4.2).repeatForever(autoreverses: true)) {
                    blotPulse = true
                }
            }
    }

    /// The nib: a small ink-drop pulsing at the end of the line while it writes.
    private var nibDot: some View {
        Circle()
            .fill(room.accent)
            .frame(width: 5, height: 5)
            .opacity(nibPulse ? 0.95 : 0.25)
            .scaleEffect(nibPulse ? 1.1 : 0.85)
            .onAppear {
                nibPulse = false
                withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) {
                    nibPulse = true
                }
            }
    }

    // MARK: Exchange loop

    private func runExchange(_ lines: [Line]) async {
        var index = 0
        try? await Task.sleep(for: .milliseconds(700))
        while !Task.isCancelled {
            let line = lines[index]
            lineIndex = index
            withAnimation(nil) { absorbed = false }

            if reduceMotion {
                shownCount = line.text.count
            } else {
                shownCount = 0
                // one character every 38 ms, as the design's rAF pacing
                for n in 1...line.text.count {
                    try? await Task.sleep(for: .milliseconds(38))
                    if Task.isCancelled { return }
                    shownCount = n
                }
            }

            // questions hold briefly, replies linger
            var hold: Double = line.hand == .you ? 1.9 : 3.2
            if reduceMotion { hold += 3.0 }
            try? await Task.sleep(for: .seconds(hold))
            if Task.isCancelled { return }

            withAnimation(.easeIn(duration: 1.4)) { absorbed = true }
            let gap: Double = line.hand == .you ? 1.55 : 1.9
            try? await Task.sleep(for: .seconds(gap))
            if Task.isCancelled { return }

            index = index + 1 >= lines.count ? 1 : index + 1
        }
    }
}

// MARK: - Book spine

struct BookSpineView: View {
    let book: Book
    let focused: Bool
    let tap: () -> Void
    let hide: () -> Void
    @Environment(\.room) private var room
    @Environment(\.reduceInkMotion) private var reduceMotion
    @State private var oraclePulse = false

    var body: some View {
        Button(action: tap) {
            GeometryReader { geo in
                ZStack(alignment: .bottom) {
                    if book.suggested {
                        suggestedBloom(width: geo.size.width)
                    }
                    spine(height: geo.size.height * 0.86)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
            .overlay(alignment: .top) { whisperBubble.offset(y: -40) }
            .overlay(alignment: .bottom) {
                if book.resting {
                    SmallCapsLabel(text: "resting", size: 10, tracking: 1.2, color: Color(hex: 0x6B5A43))
                        .italic()
                        .offset(y: 16)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: 116, maxHeight: .infinity)
        // The peek is a bouncing 18pt translation on every tap; under the
        // setting the book brightens in place instead of hopping.
        .offset(y: focused && !reduceMotion ? -18 : 0)
        .opacity(book.resting ? 0.62 : 1)
        .inkAnimation(.spring(duration: 0.3, bounce: 0.15), value: focused, reduce: reduceMotion)
        .contextMenu {
            Button("Hide from the shelf", systemImage: "eye.slash", action: hide)
        }
        .accessibilityLabel("\(book.name). \(book.whisper)")
        // The spine says "resting", "locked" and "suggested" in ornament
        // only — a candle bloom, a pulsing lock, a dimmed cover.
        .accessibilityValue(spokenState)
        .accessibilityHint(focused
            ? "Tap again to open."
            : "Tap to peek, tap again to open.")
    }

    /// What the spine's ornament means, said out loud.
    private var spokenState: String {
        var notes: [String] = []
        if book.locked { notes.append("Locked — only your hand may open it") }
        if book.resting { notes.append("Resting") }
        if book.suggested { notes.append("Awake tonight") }
        return notes.joined(separator: ". ")
    }

    private func spine(height: CGFloat) -> some View {
        UnevenRoundedRectangle(
            topLeadingRadius: 3, bottomLeadingRadius: 3,
            bottomTrailingRadius: 3, topTrailingRadius: 4
        )
        .fill(
            LinearGradient(
                stops: [
                    .init(color: book.spineTop, location: 0),
                    .init(color: book.accent, location: 0.3),
                    .init(color: book.spineBottom, location: 1),
                ],
                startPoint: .top, endPoint: .bottom
            )
        )
        .overlay {
            // leather sheen
            LinearGradient(
                stops: [
                    .init(color: .white.opacity(0.14), location: 0),
                    .init(color: .black.opacity(0.06), location: 0.22),
                    .init(color: .black.opacity(0.30), location: 0.6),
                    .init(color: .black.opacity(0.42), location: 1),
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .clipShape(RoundedRectangle(cornerRadius: 3))
        }
        .overlay {
            // gilded title, reading up the spine; overlaid so its unrotated
            // layout width can never widen the spine itself
            Text(book.name)
                .font(InkFont.display(19))
                .kerning(0.8)
                .foregroundStyle(
                    LinearGradient(colors: [Ink.goldTitleTop, Ink.candle], startPoint: .leading, endPoint: .trailing)
                )
                .shadow(color: .black.opacity(0.3), radius: 0, y: 1)
                .lineLimit(1)
                .fixedSize()
                // Rotated inside a spine capped at 116pt: unrestrained, this
                // becomes ~59pt of gilt running across its neighbours at the
                // accessibility sizes. VoiceOver reads the full title from
                // the button's own label regardless.
                .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                .rotationEffect(.degrees(-90))
        }
        .overlay(alignment: .top) { ribbon.offset(y: -6) }
        .overlay(alignment: .top) {
            if book.locked {
                LockGlyph().padding(.top, 12)
            }
        }
        .overlay(alignment: .bottom) { monogramRing.padding(.bottom, 12) }
        .compositingGroup()
        .shadow(
            color: .black.opacity(focused ? 0.6 : 0.65),
            radius: focused ? 20 : 12,
            y: focused ? 18 : 10
        )
        // suggested glow: cast by the spine's own silhouette so it hugs the
        // book instead of spilling over its neighbours
        .shadow(
            color: book.suggested
                ? Ink.candleBright.opacity(reduceMotion ? 0.5 : (oraclePulse ? 0.65 : 0.3))
                : .clear,
            radius: oraclePulse && !reduceMotion ? 17 : 11
        )
        .shadow(
            color: book.suggested
                ? Ink.candle.opacity(reduceMotion ? 0.3 : (oraclePulse ? 0.4 : 0.18))
                : .clear,
            radius: oraclePulse && !reduceMotion ? 30 : 22
        )
        .onAppear {
            guard book.suggested, !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 3.2).repeatForever(autoreverses: true)) {
                oraclePulse = true
            }
        }
        .frame(height: height)
    }

    private var ribbon: some View {
        UnevenRoundedRectangle(
            topLeadingRadius: 0, bottomLeadingRadius: 2,
            bottomTrailingRadius: 2, topTrailingRadius: 0
        )
        .fill(LinearGradient(colors: [book.accent, .mix(book.accentHex, 0.6, 0x000000)], startPoint: .top, endPoint: .bottom))
        .frame(width: 11, height: 46)
        .opacity(0.9)
    }

    private var monogramRing: some View {
        Circle()
            .stroke(Ink.goldTitleTop.opacity(0.45), lineWidth: 1)
            .frame(width: 32, height: 32)
            .overlay(
                Text(book.monogram)
                    .font(InkFont.display(18))
                    .foregroundStyle(Ink.goldTitleTop)
            )
            .opacity(0.9)
    }

    private var whisperBubble: some View {
        Text(book.whisper)
            .font(InkFont.bodyItalic(13.5))
            .foregroundStyle(room.whisperInk)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 13)
            .padding(.vertical, 5)
            .background(Capsule().fill(room.whisperBG))
            .background(.ultraThinMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.55), radius: 10, y: 8)
            .opacity(focused ? 1 : 0)
            .offset(y: focused || reduceMotion ? 0 : 5)
            .inkAnimation(.easeOut(duration: 0.3), value: focused, reduce: reduceMotion)
            .allowsHitTesting(false)
            // The whisper is already in the spine's own label.
            .accessibilityHidden(true)
    }

    /// Candle-pool at the Oracle's feet. Sized to the spine's own column —
    /// an unconstrained ellipse here fills the whole shelf row and washes
    /// over the neighbouring books.
    private func suggestedBloom(width: CGFloat) -> some View {
        Ellipse()
            .fill(
                RadialGradient(
                    stops: [
                        .init(color: room.oracleBloom.opacity(0.55), location: 0),
                        .init(color: .clear, location: 0.75),
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: width * 0.55
                )
            )
            .frame(width: width, height: width * 0.8)
            .blur(radius: 9)
            .offset(y: 12)
            .allowsHitTesting(false)
    }
}
