import SwiftUI
import PencilKit
import InkCore
import InkAnalytics

/// The core surface: one screen, many states. Zero chrome while writing —
/// per-Book paper, hand and ink; the engine (PageInteractor) drives the
/// write → rest → absorb → answer loop underneath.
///
/// The tool tray, the history thread and the develop frame live in their own
/// files (`PageToolTray`, `PageHistoryThread`, `Design/DevelopFrame`); what
/// remains here is layout, status reactions, and the handoff between them.
struct PageView: View {
    @Bindable var model: AppModel
    @State private var interactor: PageInteractor
    @State private var canvasAbsorbed = false
    @State private var developStep = 0
    @State private var restSettled = false
    @State private var restSettleTask: Task<Void, Never>?
    @State private var openerHeight: CGFloat = 0
    /// Height of the whole opening block (opener + starter) — the status
    /// marginalia hangs just below it, wherever it currently ends.
    @State private var topBlockHeight: CGFloat = 0
    @State private var showHandPicker = false
    /// `.answered` also lands from revisits and canvas restores; only an
    /// exchange sent this visit is the value moment the ritual ask waits for.
    @State private var sentThisVisit = false
    /// In-fiction acknowledgement after a report lands; fades on its own.
    @State private var reportAck: String?
    @State private var reportAckTask: Task<Void, Never>?
    /// The clip filling the screen (task J5), and the Keeper's one-time
    /// consent gate in front of the first sealed page to travel (task J6).
    @State private var immersiveClip: ImmersiveClip?
    @State private var askingKeeperConsent = false
    /// The shop, over this page rather than instead of it — see `VialsSheet`.
    @State private var showingVials = false
    /// Pages from earlier visits fold into the thread only while this holds
    /// them open — the history pill's state.
    @State private var showEarlier = false
    /// Natural height of the reply pane's content — the centered overlay on
    /// the single-page layout sizes itself to this, capped to the page.
    @State private var replyPaneHeight: CGFloat = 0
    /// VoiceOver lands on the hand card's title when it rises (A-3).
    @AccessibilityFocusState private var handCardFocused: Bool
    @Environment(\.room) private var room
    @Environment(\.reduceInkMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    /// Read through the model, not captured at init: choosing a hand on the
    /// hand card must re-ink the opener and the replies while the page is
    /// still open.
    private var book: Book { model.activeBook }
    private let archive: PageArchive
    private let analytics: Analytics
    private let di: AppDI
    private var net: Reachability { .shared }

    init(model: AppModel, di: AppDI) {
        self.model = model
        self.archive = di.archive
        self.analytics = di.analytics
        self.di = di
        _interactor = State(initialValue: PageInteractor(
            proxy: di.proxy, analytics: di.analytics, book: model.activeBookID,
            archive: di.archive, drafts: di.drafts
        ))
    }

    var body: some View {
        GeometryReader { geo in
            let spread = geo.size.width > geo.size.height && model.spreadLayout
            ZStack(alignment: .topLeading) {
                paperBackground

                VStack(alignment: .leading, spacing: 0) {
                    header
                    if spread {
                        HStack(alignment: .top, spacing: 0) {
                            writingPage
                                .padding(.trailing, 48)
                            Rectangle()
                                .fill(Ink.ink.opacity(0.13))
                                .frame(width: 1)
                            rightPage
                                .padding(.leading, 48)
                        }
                        .frame(maxHeight: .infinity)
                    } else {
                        // One page, all of it writable: the reply floats at
                        // the CENTER of the page, sized to what it carries —
                        // a short answer is a small island, a long one grows
                        // to a cap and scrolls within itself. It takes
                        // touches only when it has something to show, and
                        // fades out of the way the moment the writer takes
                        // the page back.
                        writingPage
                            .overlay(alignment: .center) {
                                rightPage
                                    .frame(maxWidth: 620)
                                    .frame(height: min(replyPaneHeight, geo.size.height * 0.62))
                                    .opacity(writerHasThePage ? 0 : 1)
                                    .inkAnimation(
                                        .easeOut(duration: 0.35),
                                        value: writerHasThePage, reduce: reduceMotion
                                    )
                                    .inkAnimation(
                                        .easeOut(duration: 0.3),
                                        value: replyPaneHeight, reduce: reduceMotion
                                    )
                                    .allowsHitTesting(replySideActive && !writerHasThePage)
                            }
                    }
                }
                .padding(EdgeInsets(top: 64, leading: 56, bottom: 40, trailing: 56))

                backPill
                rememberedRibbon

                if showHandPicker {
                    handCard
                }

                if let target = model.reportTarget {
                    ReportSheet(
                        entry: target,
                        book: book,
                        submitter: di.proxy,
                        analytics: di.analytics,
                        onClose: { model.reportTarget = nil },
                        onSent: {
                            model.reportTarget = nil
                            acknowledgeReport()
                        }
                    )
                }

                if askingKeeperConsent {
                    KeeperClipConsent(
                        onCancel: { askingKeeperConsent = false },
                        onAgree: {
                            askingKeeperConsent = false
                            model.grantKeeperClipConsent()
                            interactor.requestVideo()
                        }
                    )
                }

                if showingVials {
                    VialsSheet(model: model) {
                        withAnimation(.easeOut(duration: reduceMotion ? 0.15 : 0.25)) {
                            showingVials = false
                        }
                        // Re-read the purse on the way out. If it is no longer
                        // empty the offer revives itself, so a reader who just
                        // bought a vial finds the page ready rather than a
                        // spent card they have to work out how to restart.
                        interactor.refreshWallet()
                    }
                }
            }
            // The clip goes THROUGH the page: a full-screen cover over the
            // whole room, not a sheet stacked on the reply pane.
            .fullScreenCover(item: $immersiveClip) { clip in
                ImmersiveClipView(url: clip.url) { immersiveClip = nil }
                    .onAppear { interactor.recordImmersiveOpen() }
            }
        }
        .onChange(of: interactor.status) { _, status in
            react(to: status)
        }
        .onAppear { consumeRevisit() }
        // Leaving the page tears the view — and this interactor — down. An
        // exchange left running would stream to completion against a dead
        // canvas: moment spent, reply filed nowhere (audit D-4). Cancelling
        // here propagates the disconnect, and the server releases the hold.
        .onDisappear { interactor.pageWillDisappear() }
        // Jetsam gives no warning; leaving the foreground is the last
        // reliable moment to put the unsent page on disk (audit D-1).
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { interactor.saveDraftNow() }
        }
    }

    /// The exchange currently standing on the reply pane, when — and only
    /// when — it is a completed, archived reply. Streaming and failed
    /// exchanges have no entry to hand back, so nothing mid-flight is ever
    /// reportable.
    private var reportableEntry: PageArchive.Entry? {
        guard interactor.status == .answered, let id = interactor.displayedEntryID else {
            return nil
        }
        return archive.entries(for: book.id).first { $0.id == id }
    }

    /// "the binder has taken note" — QuietBanner marginalia, never an alert.
    private func acknowledgeReport() {
        reportAckTask?.cancel()
        withAnimation(.easeOut(duration: 0.35)) {
            reportAck = "the binder has taken note of this page"
        }
        reportAckTask = Task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.6)) { reportAck = nil }
        }
    }

    /// Which side the writing hand rests on. Left-handed mode used to move
    /// only the status marginalia — the one element already out of the way —
    /// while the tray, the back pill and the ribbon stayed under the reaching
    /// arm. Everything the writer touches flips together now.
    private var writingEdge: Alignment {
        model.leftHanded ? .trailing : .leading
    }

    private var chromeEdge: Alignment {
        model.leftHanded ? .topTrailing : .topLeading
    }

    /// A remembered card was tapped: put that exchange back on the page —
    /// the ink on the canvas, the reply on the right — then clear the
    /// handoff so ordinary visits start blank.
    private func consumeRevisit() {
        guard let entry = model.revisit else { return }
        model.revisit = nil
        // Typed exchanges archive an empty drawing; the reply still returns.
        let drawing = (try? PKDrawing(data: entry.strokeData)) ?? PKDrawing()
        interactor.revisit(drawing: drawing, replyText: entry.replyText, entryID: entry.id)
    }

    // MARK: - Paper & chrome

    private var paperBackground: some View {
        RadialGradient(
            stops: [
                .init(color: .mix(book.paperHex, 0.96, 0xFFFFFF), location: 0),
                .init(color: book.paper, location: 0.46),
                .init(color: .mix(book.paperHex, 0.84, 0x6B5A43), location: 1),
            ],
            center: UnitPoint(x: 0.22, y: 0),
            startRadius: 0,
            endRadius: 1300
        )
        .ignoresSafeArea()
    }

    private var backPill: some View {
        Button { model.go(.shelf) } label: {
            HStack(spacing: 7) {
                Text("‹").font(InkFont.body(15)).foregroundStyle(Ink.inkFaded)
                    .accessibilityHidden(true) // ornament; the label carries it
                SmallCapsLabel(text: "the shelf", size: 13, tracking: 1.5, color: Ink.inkFaded)
            }
            .padding(.leading, 11)
            .padding(.trailing, 14)
            .frame(minHeight: 38)
            .background(
                Capsule()
                    .fill(Ink.ink.opacity(0.06))
                    .overlay(Capsule().stroke(Ink.ink.opacity(0.14), lineWidth: 1))
            )
        }
        .buttonStyle(PressScaleStyle())
        .padding(.top, 18)
        .padding(model.leftHanded ? .trailing : .leading, 20)
        .frame(maxWidth: .infinity, alignment: model.leftHanded ? .trailing : .leading)
    }

    private var rememberedRibbon: some View {
        Button { model.go(.remembered) } label: {
            // The bookmark alone said only "remembered", rotated and easy to
            // miss; the plain sublabel under its tail says what it opens.
            VStack(spacing: 6) {
                RibbonShape()
                    .fill(
                        LinearGradient(
                            colors: [book.accent, .mix(book.accentHex, 0.65, 0x000000)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .frame(width: 34, height: 92)
                    .shadow(color: .black.opacity(0.25), radius: 5, y: 4)
                    .overlay(alignment: .center) {
                        SmallCapsLabel(text: "remembered", size: 10, tracking: 1.1, color: Ink.parchment)
                            .fixedSize()
                            .rotationEffect(.degrees(90))
                            .offset(y: -7)
                            // Rotated inside a fixed 34×92 ribbon: this label is
                            // the one piece of type that physically cannot grow
                            // with the rest. Capped rather than allowed to run
                            // off the page — the button keeps its 44pt target and
                            // VoiceOver reads the full word regardless.
                            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                    }
                SmallCapsLabel(text: "past pages", size: 10, tracking: 1.3, color: Ink.inkFaded)
                    .fixedSize()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
        .frame(maxWidth: .infinity, alignment: model.leftHanded ? .leading : .trailing)
        .padding(model.leftHanded ? .leading : .trailing, 46)
        .ignoresSafeArea(edges: .top)
        .accessibilityLabel("Remembered pages")
        .accessibilityHint("Every page you have filled in \(book.name).")
    }

    /// Cancel is only meaningful while a send is pending, but surfacing it
    /// the instant the pen lifts made every between-words pause flash a
    /// button. It waits for the same settle beat as the rest seal.
    private var showCancelSend: Bool {
        interactor.canCancelSend && restSettled
    }

    private var header: some View {
        HStack(spacing: 16) {
            if model.leftHanded {
                PageToolTray(interactor: interactor, showCancelSend: showCancelSend, onHand: openHandCard)
                if hasEarlierPages { historyPill }
                headerTitle
            } else {
                headerTitle
                if hasEarlierPages { historyPill }
                PageToolTray(interactor: interactor, showCancelSend: showCancelSend, onHand: openHandCard)
            }
        }
        .padding(.bottom, 26)
        .padding(model.leftHanded ? .leading : .trailing, 52)
    }

    /// HISTORY — the one door to pages from earlier visits. The page opens
    /// on this visit's session alone; this pill folds the past in and out of
    /// the thread. Dims with the tray while the pen moves.
    private var historyPill: some View {
        Button {
            withAnimation(.easeOut(duration: reduceMotion ? 0.15 : 0.3)) {
                showEarlier.toggle()
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: showEarlier ? "chevron.up" : "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(showEarlier ? Ink.parchment : Ink.inkFaded)
                SmallCapsLabel(
                    text: "history", size: 11, tracking: 1.8,
                    color: showEarlier ? Ink.parchment : Ink.inkFaded
                )
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 32)
            .background(
                Capsule()
                    .fill(showEarlier ? Ink.inkFaded : Ink.ink.opacity(0.05))
                    .overlay(Capsule().stroke(Ink.ink.opacity(0.2), lineWidth: 1))
            )
            .fixedSize()
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
        .opacity(interactor.status == .inking ? 0.14 : 0.8)
        .inkAnimation(
            .easeOut(duration: 0.4), value: interactor.status == .inking, reduce: reduceMotion
        )
        .accessibilityLabel("History")
        .accessibilityValue(showEarlier ? "Showing pages from earlier visits" : "Hidden")
        .accessibilityHint(showEarlier
            ? "Hides the pages from earlier visits."
            : "Shows the pages you filled on earlier visits, above this visit's thread.")
    }

    private func openHandCard() {
        withAnimation(.easeOut(duration: reduceMotion ? 0.15 : 0.25)) {
            showHandPicker = true
        }
    }

    private func closeHandCard() {
        withAnimation(.easeOut(duration: reduceMotion ? 0.15 : 0.25)) {
            showHandPicker = false
        }
    }

    /// The hand card: re-dress this Book while its page stays in view — each
    /// choice re-inks the opener and the replies live, behind a scrim thin
    /// enough to watch it happen.
    private var handCard: some View {
        ZStack(alignment: model.leftHanded ? .topLeading : .topTrailing) {
            Color.black.opacity(0.12)
                .ignoresSafeArea()
                .onTapGesture { closeHandCard() }
                .accessibilityLabel("Close the hand card")

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("The hand it writes in")
                            .font(InkFont.display(21))
                            .foregroundStyle(room.heading)
                            .accessibilityFocused($handCardFocused)
                        Text("\(book.name) answers in this script.")
                            .font(InkFont.bodyItalic(13))
                            .foregroundStyle(room.dim)
                    }
                    Spacer(minLength: 8)
                    Button { closeHandCard() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(room.dim)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close")
                }
                .padding(EdgeInsets(top: 16, leading: 18, bottom: 6, trailing: 6))

                ScrollView(showsIndicators: false) {
                    HandPickerList(
                        ownLabel: "\(book.name)'s own",
                        ownHand: Hand.by(id: Book.by(id: book.id).hand),
                        selection: model.bookHands[book.id],
                        ownSelected: model.bookHands[book.id] == nil
                    ) { model.setHand($0, for: book.id) }
                    .padding(.bottom, 8)
                }
            }
            .frame(maxWidth: 400)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(LinearGradient(colors: [room.cardTop, room.cardBottom], startPoint: .top, endPoint: .bottom))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(room.accent.opacity(0.28), lineWidth: 1))
                    .shadow(color: .black.opacity(0.45), radius: 26, y: 12)
            )
            .frame(maxHeight: 600)
            .padding(.top, 96)
            .padding(model.leftHanded ? .leading : .trailing, 56)
        }
        .transition(.opacity)
        // The hand card floats over a live page; without .isModal the canvas
        // and tray behind the scrim stay swipe-reachable (audit A-3).
        .accessibilityAddTraits(.isModal)
        .onAppear { handCardFocused = true }
    }

    private var headerTitle: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            SmallCapsLabel(text: book.name, size: 13, tracking: 2.6, color: book.ink)
            LinearGradient(colors: [Ink.ink.opacity(0.22), .clear], startPoint: .leading, endPoint: .trailing)
                .frame(height: 1)
            SmallCapsLabel(text: Self.todayLabel, size: 12, tracking: 1.8, color: Ink.inkFaded)
        }
    }

    // MARK: - Writing page (your hand, edge to edge)

    /// The whole page is the writing surface. The opener, starter hint and
    /// status notes float OVER the canvas (hit-testing off) rather than
    /// stacking with it — so ink can land anywhere on the page, and no
    /// layout change can resize PKCanvasView mid-stroke and cancel a stroke.
    private var writingPage: some View {
        ZStack(alignment: .topLeading) {
            // ONE surface, two hands: ink when the pen is about, the
            // keyboard's script otherwise — never two inputs. The typed hand
            // starts below the opener; the pen may cross it freely.
            InkCanvasView(
                interactor: interactor,
                pencilActive: PenPresence.shared.pencilPreferred,
                inkColor: UIColor(Color(hex: model.inkColorHex)),
                typedTopInset: openerHeight + 14
            )
            .opacity(canvasAbsorbed ? 0.18 : 1)
            .blur(radius: canvasAbsorbed ? 2 : 0)
            // `.contain`, never the bare `.accessibilityElement()`: the
            // no-argument form ignores children, which hid the typed hand's
            // UITextView outright — on an iPad with no Pencil that is the
            // ONLY input, so VoiceOver users could not write at all.
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("ink-canvas")
            .accessibilityLabel("Writing surface. Write with pencil or finger anywhere on the page — or with the keyboard when no pencil is at hand; rest to send.")
            .accessibilityValue(spokenStatus)

            // The book's greeting and the starter invitation open the page
            // together, at the top. The first stroke or keystroke fades them
            // out — the whole page is the writer's — and a fresh blank page
            // brings them back. The opener keeps its layout while invisible
            // so the typed hand's inset never jumps mid-visit.
            VStack(alignment: .leading, spacing: 0) {
                Text(book.opener)
                    .font(book.handFont(26))
                    .foregroundStyle(book.ink)
                    .opacity(showOpening ? 0.92 : 0)
                    .lineSpacing(6)
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        proxy.size.height
                    } action: { openerHeight = $0 }
                if showOpening {
                    starterOpening
                        .transition(.opacity)
                }
            }
            .allowsHitTesting(false)
            .inkAnimation(.easeOut(duration: 0.4), value: showOpening, reduce: reduceMotion)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height
            } action: { topBlockHeight = $0 }
        }
        // Occlusion rule (task B6): the writing hand owns the bottom of
        // the page, so every status note is TOP-margin marginalia — just
        // under the opener; the side flips with left-handed mode.
        .overlay(alignment: chromeEdge) {
            Group {
                // The report acknowledgement borrows the status margin for a
                // beat; the regular marginalia returns when it fades.
                if let ack = reportAck {
                    QuietBanner(text: ack)
                        .transition(.opacity)
                } else {
                    statusNote
                }
            }
            .frame(maxWidth: 440, alignment: writingEdge)
            .padding(.top, topBlockHeight + 12)
            .allowsHitTesting(false)
            .inkAnimation(.easeOut(duration: 0.35), value: interactor.status, reduce: reduceMotion)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Whether the reply side has anything to show (and therefore may take
    /// touches when it overlays the single-page canvas).
    private var replySideActive: Bool {
        if !displayedReply.isEmpty || interactor.developing || !sessionThread.isEmpty {
            return true
        }
        if showEarlier && hasEarlierPages { return true }
        switch interactor.status {
        case .cooldown, .declined: return true
        default: return false
        }
    }

    /// The reply appears the way the ink disappeared — whole, rising out of
    /// the page — never streaming in token by token. While the Book is still
    /// answering, the buffered text stays below the surface; the moment the
    /// exchange completes, the full reply surfaces in one breath.
    private var displayedReply: String {
        interactor.status == .answering ? "" : interactor.streamedText
    }

    /// While the pen or the keys are moving, the single page belongs to the
    /// writer: the centered reply fades out of the way and stays away
    /// through the rest — it returns only when something new stands.
    private var writerHasThePage: Bool {
        interactor.status == .inking || interactor.status == .resting
    }

    /// A fresh blank page shows the book's greeting and the starter; the
    /// first stroke or keystroke fades them, and they stay away while a
    /// reply stands.
    private var showOpening: Bool {
        interactor.status == .idle && interactor.streamedText.isEmpty && interactor.typedDraft.isEmpty
    }

    /// What VoiceOver reads as the canvas's value. It used to be
    /// `String(describing:)` on a status with associated values, so the page
    /// literally spoke "cooldown(3600.0)" and "paywall(dailyLimit)". The
    /// in-fiction copy is the same copy the sighted page shows.
    private var spokenStatus: String {
        switch interactor.status {
        case .idle:
            return net.isOffline
                ? "A blank page. The road is dark just now — nothing can carry it yet."
                : "A blank page, waiting."
        case .inking: return "Writing."
        case .resting: return "The page waits — nothing sends while the ink is still settling."
        case .sending, .answering: return "The ink drinks into the page. \(book.name) is answering."
        case .answered: return "\(book.name) has answered. The reply is on the facing page."
        case .held: return "The page is held — nothing sends until you lift the hold."
        case .paywall: return "The ink has run dry for today."
        case .cooldown: return "The ink has run hot today, and must rest a while."
        case .declined: return declineCopy
        case .crisis: return "Opening help."
        }
    }

    /// Top-margin marginalia: the quiet in-flight statuses, styled per
    /// QuietBanner (italic, ink-faded, no red). Errors live on the reply
    /// side (`errorNote`); nothing informative ever renders in the bottom
    /// region while writing.
    @ViewBuilder
    private var statusNote: some View {
        switch interactor.status {
        case .resting:
            // The settle bounce is the promise: the page waits while the dots
            // still dance — finish the thought, nothing sends yet. Dots only:
            // every between-words pause lands here, so any caption or button
            // would nag on every breath. The send commits on its own; the
            // mechanic is taught once, in onboarding.
            SettleBounce()
                .transition(.opacity)
        case .sending, .answering:
            // The banner holds through the whole exchange: the reply no
            // longer streams, so the wait needs a voice until it surfaces.
            QuietBanner(text: "the ink drinks into the page…")
                .transition(.opacity)
        case .held:
            QuietBanner(text: "the page waits — nothing sends until you lift the hold")
                .transition(.opacity)
        default:
            // Said BEFORE the ink is committed: a writer with no road spent
            // the whole rest window and a send attempt to be told the spirit
            // was distant, with a retry that could never succeed.
            if net.isOffline {
                // Says what is true (audit D-10): the ink is kept — drafts
                // persist now — but nothing queues itself, so the page waits
                // for a hand to send it rather than promising to travel alone.
                QuietBanner(text: "the road is dark — write on; your ink is kept, and sends when the way opens")
                    .transition(.opacity)
            } else {
                EmptyView()
            }
        }
    }

    /// Cooldown and decline cards render where the answer would have:
    /// the right page in a spread, the centered island on a single
    /// screen — never over the ink the writer just laid down.
    @ViewBuilder
    private var errorNote: some View {
        switch interactor.status {
        case .cooldown:
            VStack(alignment: .leading, spacing: 12) {
                QuietBanner(text: "The ink has run hot today, and must rest a while. Come back when it has settled — or bind the notebook, and write without pause.")
                WaxSealButton(label: "bind to write without pause", diameter: 30, labelFont: InkFont.body(14)) {
                    model.go(.paywall)
                }
            }
            .padding(EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16))
            .background(parchmentCard)
            .transition(.opacity)
        case .declined:
            VStack(alignment: .leading, spacing: 12) {
                QuietBanner(text: declineCopy)
                Button {
                    interactor.retry()
                } label: {
                    Text("try again")
                        .font(InkFont.body(14))
                        .foregroundStyle(Ink.inkFaded)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 40)
                        .background(
                            Capsule()
                                .fill(Ink.ink.opacity(0.06))
                                .overlay(Capsule().stroke(Ink.ink.opacity(0.18), lineWidth: 1))
                        )
                }
                .buttonStyle(PressScaleStyle())
                .accessibilityHint(net.isOffline
                    ? "The road is still dark; this will not carry until the connection returns."
                    : "Ask the Book again.")
            }
            .padding(EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16))
            .background(parchmentCard)
            .transition(.opacity)
        default:
            EmptyView()
        }
    }

    /// A failed send says one of two different things. The decline card used
    /// to speak the raw `String(describing:)` of the mapped state as its
    /// VoiceOver hint — "pageIsQuiet" — while the sighted copy was mystical
    /// about a problem that was simply airplane mode.
    private var declineCopy: String {
        net.isOffline
            ? "The road is dark tonight — no page can travel it. Your ink is safe here; ask again when the way opens."
            : "The spirit is distant tonight. Your page is safe — I will answer when the candle steadies."
    }

    /// The invitation, directly under the opener — the ghost prompt sits
    /// exactly where the typed hand begins, so it reads as a placeholder
    /// the writer's own words replace.
    private var starterOpening: some View {
        VStack(alignment: .leading, spacing: 12) {
            SmallCapsLabel(text: "take up your pen", size: 12, tracking: 2.2, color: Ink.inkFaded)
            Text(book.starterPrompt)
                .font(InkFont.hand("Caveat-Regular", 26))
                .foregroundStyle(Ink.ink.opacity(0.4))
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .frame(maxWidth: 620, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Ink.ink.opacity(0.03))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Ink.ink.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                        )
                )
        }
        .padding(.top, 18)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Take up your pen. For instance: \(book.starterPrompt)")
    }

    // MARK: - Right page (the Book's reply)

    /// This visit's earlier exchanges, oldest first — the running thread
    /// above the live reply. Only the session: a fresh visit starts clear.
    /// The exchange currently standing on the reply pane is skipped so it
    /// never renders twice.
    private var sessionThread: [PageArchive.Entry] {
        archive.entries(for: book.id)
            .filter {
                interactor.sessionEntryIDs.contains($0.id)
                    && $0.id != interactor.displayedEntryID
            }
            .reversed()
    }

    /// Pages from earlier visits, oldest first — on the page only while the
    /// history pill holds them open. Free tier: pages past the fade line stay
    /// in Remembered (ghosted, bind to keep) and never render here, or the
    /// thread would hand out what the fade has already claimed.
    private var earlierPages: [PageArchive.Entry] {
        archive.entries(for: book.id)
            .filter { entry in
                !interactor.sessionEntryIDs.contains(entry.id)
                    && entry.id != interactor.displayedEntryID
                    && (model.bound
                        || Date.now.timeIntervalSince(entry.createdAt) <= PageArchive.freeFadeAfter)
            }
            .reversed()
    }

    private var hasEarlierPages: Bool { !earlierPages.isEmpty }

    private var rightPage: some View {
        // Hoisted: each of these is an O(n) filter pass per access, and the
        // body would otherwise re-run them on every render.
        let thread = sessionThread
        let earlier = showEarlier ? earlierPages : []
        return ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                if !earlier.isEmpty || !thread.isEmpty {
                    // Earlier visits stand above the session; both are
                    // chronological, so one thread reads straight through.
                    PageHistoryThread(entries: earlier + thread, book: book) { entry in
                        model.reportTarget = entry
                    }
                    .padding(.top, 30)
                }
                errorNote
                    .frame(maxWidth: 440, alignment: .leading)
                    .padding(.top, 30)
                if !displayedReply.isEmpty {
                    reply
                        .padding(.top, 30)
                        .transition(InkMotion.arrival(.inkSurface, reduce: reduceMotion))
                        // Long-press to report — only once the exchange has
                        // completed and archived; nothing mid-stream.
                        .modifier(ReportableReply(entry: reportableEntry) { entry in
                            model.reportTarget = entry
                        })
                }
                // The server decides modality: the frame appears when an
                // image slot opens (darkroom running), stays for the finished
                // picture, and quietly withdraws if the develop failed.
                if interactor.developing
                    && (interactor.imageURL != nil || interactor.status == .answering) {
                    developSection
                        .padding(.top, 30)
                }

                movingPictureSection
                    .padding(.top, 22)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            // What the pane would naturally take — the single-page layout
            // sizes its centered island to this.
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height
            } action: { replyPaneHeight = $0 }
            // Mirror of the absorb veil (0.9s easeIn out of sight): the
            // reply surfaces over the same beat, blurred-and-faint to sharp.
            .animation(
                .easeOut(duration: reduceMotion ? 0.3 : 0.9),
                value: displayedReply.isEmpty
            )
        }
        // The thread reads like a chat: the newest words wait at the foot of
        // the page, the past scrolls up behind them.
        .defaultScrollAnchor(.bottom)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var reply: some View {
        HStack(alignment: .top, spacing: 20) {
            LinearGradient(
                colors: [Ink.ink.opacity(0.05), Ink.ink.opacity(0.22), Ink.ink.opacity(0.05)],
                startPoint: .top, endPoint: .bottom
            )
            .frame(width: 2)

            // No `.accessibilityLabel` here on purpose: the reply text IS the
            // element's label, and that is what both VoiceOver and the
            // reply-pane UITest read.
            Text(displayedReply)
                .font(book.handFont(24))
                .foregroundStyle(book.ink)
                .lineSpacing(7)
                .frame(maxWidth: 720, alignment: .leading)
                .accessibilityIdentifier("reply-pane")
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Moving pictures (Epic J)

    /// The whole of the video surface, on the reply side where the answer
    /// lives — never in the bottom region the writing hand owns (task B6's
    /// occlusion rule holds here too).
    @ViewBuilder
    private var movingPictureSection: some View {
        switch interactor.video {
        case .none:
            EmptyView()
        case .offered:
            MovingPictureOffer(
                book: book,
                wallet: interactor.wallet,
                isOffline: net.isOffline,
                onRequest: requestMovingPicture,
                onOpenVials: openVials
            )
        case .generating:
            MovingPictureDeveloping(book: book)
        case .delivered(let url):
            MovingPictureFrame(url: url, book: book) { immersiveClip = ImmersiveClip(url: url) }
        case .failed(let line):
            // The refund promise is part of the copy — the reader is told, in
            // the same breath, that nothing was spent.
            QuietBanner(text: line)
                .frame(maxWidth: 440, alignment: .leading)
        case .needsVials(let line):
            // Not an apology: nothing was charged, and the thing standing
            // between the reader and their picture is a purchase they can make
            // from here without losing the page.
            VStack(alignment: .leading, spacing: 12) {
                QuietBanner(text: line)
                WaxSealButton(
                    label: "fill the vials",
                    diameter: 30,
                    labelFont: InkFont.bodyItalic(14),
                    action: openVials
                )
            }
            .padding(EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16))
            .frame(maxWidth: 440, alignment: .leading)
            .background(parchmentCard)
        }
    }

    /// Opens the shop over the page. Deliberately not `model.go(.wallet)`:
    /// RootView rebuilds PageView on navigation, and the reply the reader is
    /// trying to animate would not survive the trip.
    private func openVials() {
        withAnimation(.easeOut(duration: reduceMotion ? 0.15 : 0.25)) {
            showingVials = true
        }
    }

    /// The tap. The Keeper's first clip stops here for consent; everything
    /// else goes straight to the interactor, which is the only thing that can
    /// start a generation.
    private func requestMovingPicture() {
        if book.locked && !model.keeperClipConsentGranted {
            withAnimation(.easeOut(duration: reduceMotion ? 0.15 : 0.25)) {
                askingKeeperConsent = true
            }
            return
        }
        interactor.requestVideo()
    }

    // MARK: - Develop frame (Artist)

    private var developSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // isMoving is false because this is the STILL develop (the Artist's
            // picture). A moving picture is a separate, user-triggered request
            // and renders in `movingPictureSection` — nothing here ever spends
            // a vial.
            DevelopFrame(book: book, step: developStep, isMoving: false, imageURL: interactor.imageURL)
                .frame(maxWidth: 420)
            Text("developed from your page")
                .font(InkFont.bodyItalic(13))
                .foregroundStyle(Ink.inkFaded)
                .frame(maxWidth: 420, alignment: .leading)
        }
        .onAppear { runDevelop() }
        .onChange(of: interactor.imageURL) { _, url in
            guard url != nil else { return }
            withAnimation(.easeInOut(duration: reduceMotion ? 0.3 : 1.1)) { developStep = 3 }
        }
    }

    /// Darkroom reveal pacing while fal paints: (seconds to wait, develop
    /// step to reach). Step 3 never comes from here — see runDevelop.
    private static let developScript: [(delay: Double, step: Int)] = [(0.9, 1), (1.0, 2), (1.2, 3)]

    /// The darkroom drifts to step 2 on its own while fal paints; the full
    /// reveal (step 3) is gated on the real picture arriving.
    private func runDevelop() {
        guard developStep == 0 else { return }
        if reduceMotion {
            developStep = interactor.imageURL != nil ? 3 : 2
            return
        }
        if interactor.imageURL != nil {
            developStep = 3
            return
        }
        Task {
            for (delay, step) in Self.developScript where step < 3 {
                try? await Task.sleep(for: .seconds(delay))
                guard developStep < step else { continue }
                withAnimation(.easeInOut(duration: 1.1)) { developStep = step }
            }
        }
    }

    private var parchmentCard: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Ink.ink.opacity(0.04))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Ink.ink.opacity(0.14), lineWidth: 1))
    }

    // MARK: - Status reactions

    private func react(to status: PageInteractor.PageStatus) {
        settleRestAffordances(for: status)
        announce(status)
        switch status {
        case .sending:
            // The deadline passed and the page went without the writer
            // touching anything — this tap is the only way they can know.
            Feel.shared.play(.sendCommitted)
            // A fresh exchange gets a fresh darkroom.
            developStep = 0
            sentThisVisit = true
            withAnimation(.easeIn(duration: reduceMotion ? 0.3 : 0.9)) {
                canvasAbsorbed = true
            }
        case .inking:
            withAnimation(.easeOut(duration: 0.2)) {
                canvasAbsorbed = false
            }
        case .answered:
            // Only an exchange sent this visit pulses — `.answered` also
            // lands from revisits and restores, which must stay silent.
            if sentThisVisit { Feel.shared.play(.replyArrived) }
            // The interactor has archived and removed the strokes; lift the
            // absorption veil so the (now empty) canvas is ready to write on.
            withAnimation(.easeOut(duration: 0.25)) {
                canvasAbsorbed = false
            }
            // The value moment: the first answered page, and only then, earns
            // the notification ask — mirroring how the paywall waits.
            if sentThisVisit {
                Task {
                    if let granted = await model.promptRitualIfNeeded() {
                        await analytics.track(.notificationPermissionAnswered(granted: granted))
                    }
                }
            }
        case .declined, .cooldown:
            // A quiet no — deliberately softer than an error.
            Feel.shared.play(.refusal)
            // Failed send: the ink must come back at FULL strength — an error
            // may never leave the page ghosted.
            withAnimation(.easeOut(duration: 0.2)) {
                canvasAbsorbed = false
            }
        case .paywall:
            canvasAbsorbed = false
            model.go(.paywall)
        case .crisis:
            // Deliberately no haptic and no sound — the crisis room is still.
            canvasAbsorbed = false
            model.go(.crisis)
        default:
            break
        }
    }

    /// The reply surfaces silently. A VoiceOver user rested their pen, heard
    /// nothing for eight seconds, and had no signal that the Book had
    /// answered at all — they had to go hunting for changed content.
    private func announce(_ status: PageInteractor.PageStatus) {
        switch status {
        case .answered, .declined, .cooldown:
            AccessibilityNotification.Announcement(spokenStatus).post()
        default:
            break
        }
    }

    /// The cancel button used to pop in the instant the pen lifted — a flash
    /// on every between-words pause. It now fades in only once the rest has
    /// held for a beat (commit fires at 4s, so 1.1s still leaves a usable
    /// window), and vanishes the moment any other status lands. The settle
    /// bounce, by contrast, shows for the whole rest window.
    private func settleRestAffordances(for status: PageInteractor.PageStatus) {
        restSettleTask?.cancel()
        guard status == .resting else {
            restSettled = false
            return
        }
        restSettleTask = Task {
            try? await Task.sleep(for: .milliseconds(1100))
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.35)) { restSettled = true }
        }
    }

    // MARK: - Date

    private static let ordinals = [
        "first", "second", "third", "fourth", "fifth", "sixth", "seventh", "eighth",
        "ninth", "tenth", "eleventh", "twelfth", "thirteenth", "fourteenth", "fifteenth",
        "sixteenth", "seventeenth", "eighteenth", "nineteenth", "twentieth", "twenty-first",
        "twenty-second", "twenty-third", "twenty-fourth", "twenty-fifth", "twenty-sixth",
        "twenty-seventh", "twenty-eighth", "twenty-ninth", "thirtieth", "thirty-first",
    ]

    private static var todayLabel: String {
        let day = Calendar.current.component(.day, from: .now)
        let month = Date.now.formatted(.dateTime.month(.wide)).lowercased()
        return "the \(ordinals[day - 1]) of \(month)"
    }
}
