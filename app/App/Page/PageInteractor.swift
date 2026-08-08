import Foundation
import PencilKit
import InkCore
import InkNet
import InkMoney
import InkSafety
import InkAnalytics

/// Seam for exchange-lifecycle tests (dev spec §3): `ProxyClient` is the
/// live conformer; tests script the stream to drive both resolution paths.
protocol ExchangeProxying: Sendable {
    func exchange(
        payload: SnapshotPayload, book: BookID, context: PageContext, ticket: UploadTicket?
    ) -> AsyncThrowingStream<ReplyChunk, Error>
    func preupload(_ payload: SnapshotPayload) async throws -> UploadTicket
    func abort(_ ticket: UploadTicket) async
    /// A moving picture, asked for because the reader tapped (task J4). The
    /// `videoID` is the retry key: asking twice with the same one yields one
    /// clip and one charge.
    func video(briefID: String, videoID: UUID) -> AsyncThrowingStream<ReplyChunk, Error>
    func wallet() async throws -> WalletView
}

extension ProxyClient: ExchangeProxying {}

/// The shell around the pure engine: feeds clock + stroke events into
/// `IdleSendMachine`, executes its effects (speculative upload, commit,
/// abort), runs the gate before any model call, and streams the reply through
/// `CrisisInterceptor` → `ReplyAssembler`. All product logic lives in the
/// packages; this class only wires them to PencilKit, timers, and the network.
@Observable
@MainActor
final class PageInteractor {
    enum PageStatus: Equatable {
        case idle
        case inking
        case resting
        case sending
        case answering
        case answered
        case held
        case paywall(PaywallTrigger)
        case cooldown(TimeInterval)
        case declined(String)
        case crisis(String)
    }

    private(set) var status: PageStatus = .idle
    private(set) var streamedText = ""
    /// The archived entry currently standing on the reply page (the exchange
    /// that just completed, or a revisited one) — the history thread skips it
    /// so the same reply never renders twice.
    private(set) var displayedEntryID: UUID?
    /// The session: entries archived during THIS visit to the page, plus a
    /// revisited one. The page's thread shows only these — every earlier
    /// visit's pages wait behind the history control. A fresh visit starts
    /// with an empty set, so the page opens clear.
    private(set) var sessionEntryIDs: Set<UUID> = []
    private(set) var ttfsMS: Int?
    /// Develop pass (Artist): the server opened an image slot this exchange.
    private(set) var developing = false
    /// The finished picture, once the darkroom delivers it.
    private(set) var imageURL: URL?

    // MARK: - Moving pictures (Epic J)

    /// Where the moving picture stands on this page. `offered` is the whole
    /// of the affordance's condition: the page can only offer what the Book
    /// judged a scene, and it offers — it never acts.
    enum VideoState: Equatable {
        case none
        /// The Book judged this reply convertible; the page may offer.
        case offered(ConvertibilityVerdict)
        /// The reader tapped and the picture is developing.
        case generating
        /// The clip is on the page.
        case delivered(URL)
        /// It did not arrive; the credit went back. Carries the in-fiction line.
        case failed(String)
        /// It did not arrive because there was nothing to spend. Distinct from
        /// `.failed` because the way forward is the shop, not a retry — and
        /// nothing was charged, so this is not really a failure at all.
        case needsVials(String)
    }

    private(set) var video: VideoState = .none
    /// The verdict for the reply standing on the page, held SEPARATELY from
    /// the state so it survives a failed attempt. A reader who taps with an
    /// empty purse, buys a vial and comes back must find the offer still
    /// there — otherwise they have paid for a moment they can no longer spend
    /// without writing a whole new page.
    private var offer: ConvertibilityVerdict?
    /// What a tap would spend, as the server last reported it. Nil until the
    /// wallet is read — the affordance simply says less until then, and the
    /// server decides for real either way.
    private(set) var wallet: WalletView?

    private let proxy: any ExchangeProxying
    private let analytics: Analytics
    private let book: BookID
    private let archive: (any PageArchiving)?
    /// Where unsent work survives the view (audit D-1): every rest, keystroke
    /// pause, and scene-phase change writes here; `attach(canvas:)` reads it
    /// back. Nil in harnesses that must not touch the user's drafts.
    private let drafts: (any PageDraftStoring)?
    /// Tier + durable daily counters. Both halves come from one accounting, so
    /// the gate can never read a count the completed exchange never records.
    private let entitlements: PageEntitlements
    private let memory: any MemoryProviding

    // Gentler than the machine defaults (2s/3s): writing is thought, and the
    // pause between words must never feel like a countdown. The settle bounce
    // in the page margin shows the window is open.
    private var machine = IdleSendMachine(speculateAfter: 2.5, commitAfter: 4.0)
    private weak var canvas: PKCanvasView?
    private var tickTask: Task<Void, Never>?
    private var draftSaveTask: Task<Void, Never>?
    private var exchangeTask: Task<Void, Never>?
    /// The in-flight generation (task J4). Held so leaving the page cancels
    /// it — and cancelling is what makes the server release the hold.
    private var videoTask: Task<Void, Never>?
    private var walletTask: Task<Void, Never>?
    /// The gate hop between `commitSend` and the model call. Cancelled by
    /// anything that abandons the pending send, so a denied or superseded
    /// commit can never start an exchange behind the user's back.
    private var gateTask: Task<Void, Never>?

    /// The typed page committed to the current exchange — captured at commit
    /// so the archive can file it even after the draft field clears.
    private var sentTypedText: String?
    private var sentStrokeCount = 0
    /// Strokes already accounted for BEFORE the in-flight send — what a
    /// failed send rolls `sentStrokeCount` back to, so standing ink never
    /// reads as already absorbed (audit D-6).
    private var sentBase = 0
    /// The exact drawing committed to the in-flight exchange (audit D-3):
    /// the archive files THIS on completion, never whatever stands on the
    /// canvas by then — ink laid down while the Book answers belongs to the
    /// next exchange, not this one.
    private var sentDrawing: PKDrawing?
    /// The in-flight exchange sent the typed hand alone (audit M-5): the
    /// pencil strokes standing on the page were never in its snapshot, and
    /// its completion must leave them exactly as they stand — unsent.
    private var sentTypedOnly = false
    /// The writer took the page back mid-stream (audit M-3): a stroke began
    /// while the Book was still answering. Purely visual — the exchange
    /// logic never reads it; PageView observes it to lift the absorb veil so
    /// the new ink lands at full strength, not on 18%-opacity paper.
    private(set) var writerReclaimed = false
    /// Monotonic token for the exchange lifecycle (audit D-2/D-8): only the
    /// task holding the current generation may write status, archive, or
    /// clear the in-flight flag. A cancelled or superseded stream can then
    /// never clobber the page that replaced it.
    private var exchangeGeneration = 0
    /// True from commit until the exchange resolves — the one-send-at-a-time
    /// guard. The rest cadence stays live during a stream (the canvas does),
    /// so without this a pause mid-answer committed and billed a second
    /// exchange for the same page.
    private var exchangeInFlight = false
    private var previousDigest: String?
    /// The exchange this page last completed — the Book's only continuity with
    /// what the user can still see on the right-hand page.
    private var lastTurn: PageContextBuilder.Turn?

    // Lazy so the callback can capture `self`; `@Observable` does not wrap
    // lazy storage, and nothing observes the upload window anyway.
    @ObservationIgnored
    private lazy var upload = SpeculativeUpload(
        proxy: proxy,
        onStateChange: { [weak self] event in
            guard let self else { return }
            self.perform(self.machine.handle(event))
        }
    )

    init(
        proxy: any ExchangeProxying,
        analytics: Analytics,
        book: BookID = .oracle,
        archive: (any PageArchiving)? = nil,
        drafts: (any PageDraftStoring)? = nil,
        entitlements: PageEntitlements = LiveCommerce.page,
        memory: any MemoryProviding = EmptyMemoryProvider()
    ) {
        self.proxy = proxy
        self.analytics = analytics
        self.book = book
        self.archive = archive
        self.drafts = drafts
        self.entitlements = entitlements
        self.memory = memory
    }

    func attach(canvas: PKCanvasView) {
        self.canvas = canvas
        if let drawing = pendingRestore {
            pendingRestore = nil
            restore(drawing)
            return
        }
        // Rehydrate the unsent page (audit D-1): the view — and this
        // interactor — die on every navigation, so whatever the writer left
        // unsent comes back from the draft store, accounted strokes and all.
        guard let draft = drafts?.load(book: book) else { return }
        if let drawing = try? PKDrawing(data: draft.strokeData), !drawing.strokes.isEmpty {
            canvas.drawing = drawing
            // The delegate saw the restore as grown stroke count and may have
            // armed the rest cadence; restored ink is not freshly rested ink.
            tickTask?.cancel()
            machine.reset()
        }
        typedDraft = draft.typedText
        sentStrokeCount = min(draft.accountedStrokeCount, canvas.drawing.strokes.count)
        canvas.undoManager?.removeAllActions()
    }

    // MARK: - Revisiting a remembered page

    /// A remembered exchange waiting for the canvas to attach — revisit can
    /// arrive before the page's PKCanvasView exists.
    private var pendingRestore: PKDrawing?

    /// True for the rest of the visit once a revisit arrived over unsent work
    /// (audit H-2): the draft file holds the writer's own standing page, and
    /// while this is set no save may overwrite it and no clear may delete it —
    /// leaving the revisit rehydrates the page exactly as the writer left it.
    private var revisiting = false

    /// Whether the draft FILE holds unsent work. The canvas may not have
    /// attached yet when a revisit arrives, so the file is the only witness
    /// the pending-restore path has.
    private var draftHoldsUnsentWork: Bool {
        guard let draft = drafts?.load(book: book) else { return false }
        if !draft.typedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        guard let drawing = try? PKDrawing(data: draft.strokeData) else { return false }
        return drawing.strokes.count > draft.accountedStrokeCount
    }

    /// REMEMBERED — reopen an archived exchange on the page: the user's ink
    /// returns to the canvas and the Book's reply stands on the right page,
    /// exactly as the exchange ended. The restored ink already belongs to its
    /// archived exchange, so nothing re-sends and nothing re-archives; fresh
    /// strokes on top of it start a new exchange as usual.
    func revisit(drawing: PKDrawing, replyText: String, entryID: UUID? = nil) {
        // The standing page comes first (audit H-2): reopening a memory must
        // never destroy unsent work. Checked before anything below clears —
        // on the canvas if it attached, in the draft file if it has not.
        revisiting = hasUnsentInk || draftHoldsUnsentWork
        tickTask?.cancel()
        gateTask?.cancel()
        exchangeTask?.cancel()
        // Superseding the exchange: the cancelled task's late writes are
        // fenced out by the generation token, so the teardown owns the flags.
        exchangeGeneration += 1
        exchangeInFlight = false
        sentDrawing = nil
        sentTypedOnly = false
        // A generation in flight belongs to the exchange being left; cancelling
        // is what tells the server to release its hold.
        videoTask?.cancel()
        video = .none
        offer = nil
        upload.abort()
        machine.reset()
        typedDraft = ""
        streamedText = replyText
        displayedEntryID = entryID
        // The revisited exchange IS the session now — one session at a time;
        // whatever this visit had written before stays in the archive, behind
        // the history control.
        sessionEntryIDs = entryID.map { [$0] } ?? []
        // Reopening a remembered exchange gives the Book continuity with it.
        lastTurn = PageContextBuilder.Turn(written: nil, reply: replyText)
        ttfsMS = nil
        developing = false
        imageURL = nil
        status = .answered
        if canvas != nil {
            restore(drawing)
        } else {
            pendingRestore = drawing
        }
    }

    private func restore(_ drawing: PKDrawing) {
        guard let canvas else { return }
        canvas.drawing = drawing
        // The delegate saw the restore land as grown stroke count and may
        // have armed the rest cadence; disarm it — restored ink is not
        // unsent ink.
        tickTask?.cancel()
        machine.reset()
        sentStrokeCount = drawing.strokes.count
        previousDigest = nil
        canvas.undoManager?.removeAllActions()
        status = .answered
        // With no unsent work standing, the revisited page becomes the
        // standing draft, fully accounted — a relaunch shows it exactly as
        // it stands, and re-sends nothing. Over unsent work `saveDraftNow`
        // stands down (audit H-2), and the writer's own page keeps the file.
        saveDraftNow()
    }

    // MARK: - Stroke events from the canvas

    func strokeBegan() {
        tickTask?.cancel()
        // Both hands land here — `typedDraftChanged` ends in strokeBegan/Ended
        // — so one call covers the pen and the keys.
        clearDeclinedHold()
        perform(machine.handle(.strokeBegan))
        // `.answered` too: taking the page back is what absorbs the standing
        // reply, and that begins at pen-down — the diary drinks the moment
        // the nib lands, not at the first stroke's end.
        if status == .idle || status == .resting || status == .answered {
            status = .inking
        } else if status == .sending || status == .answering {
            // Mid-stream the status belongs to the exchange — no fake
            // transition — but the writer has taken the page back, and the
            // absorb veil must lift so the new ink lands at full strength
            // (audit M-3). Visual signal only; nothing else reads it.
            writerReclaimed = true
        }
    }

    func strokeEnded() {
        scheduleDraftSave()
        perform(machine.handle(.strokeEnded(at: Date())))
        // A held page absorbs stroke events without arming the send timer.
        guard machine.state != .held else { return }
        status = .resting
        startTicking()
    }

    /// A tool use ended without laying a stroke — an eraser touch on empty
    /// paper, a cancelled/palm-rejected stroke, or an erase that only
    /// removed ink. `strokeBegan` promoted the status to `.inking` at
    /// pen-down (that is what absorbs a standing reply), and with no
    /// `strokeEnded` ever coming the page would stay stranded there:
    /// reply absorbed, tray dimmed, cadence never armed. Stand back down
    /// to what the page actually holds.
    func strokeAborted() {
        guard status == .inking else { return }
        if hasUnsentInk {
            // An erase still leaves unsent work standing — re-arm the rest
            // cadence so it sends as usual (erases never called strokeEnded,
            // so an edited page used to sit silent until the next stroke).
            perform(machine.handle(.strokeEnded(at: Date())))
            status = .resting
            startTicking()
        } else {
            machine.reset()
            status = streamedText.isEmpty ? .idle : .answered
        }
    }

    /// Any canvas mutation — a new stroke, an erase, an undo — refreshes the
    /// draft on disk, so what survives a relaunch is what the page shows.
    func canvasContentChanged() {
        scheduleDraftSave()
    }

    /// Coalesced draft write (audit D-1): strokes and keystrokes arrive in
    /// bursts, and every save re-encodes the whole drawing.
    private func scheduleDraftSave() {
        guard drafts != nil else { return }
        draftSaveTask?.cancel()
        draftSaveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard let self, !Task.isCancelled else { return }
            self.saveDraftNow()
        }
    }

    /// Immediate draft write — scene-phase changes and teardown cannot wait
    /// out the coalescing window. An empty page clears the file instead.
    func saveDraftNow() {
        guard let drafts else { return }
        draftSaveTask?.cancel()
        // A revisit stands over the writer's own unsent page (audit H-2):
        // while it does, the draft file IS that page — nothing here may
        // overwrite or clear it.
        guard !revisiting else { return }
        // A declined page has already been dropped from disk; the teardown
        // save must not put it back, or the next visit opens on the failure.
        guard !sendDeclined else { return }
        let drawing = canvas?.drawing ?? PKDrawing()
        if drawing.strokes.isEmpty,
           typedDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            drafts.clear(book: book)
            return
        }
        // An exchange still in flight has not earned its ink (audit H-1): if
        // it never resolves — teardown, jetsam, a scene-phase save racing the
        // stream — the strokes it advanced the accounting for must rehydrate
        // as unsent, so the file remembers the pre-exchange base.
        let accounted = exchangeInFlight ? sentBase : sentStrokeCount
        drafts.save(PageDraft(
            strokeData: drawing.dataRepresentation(),
            typedText: typedDraft,
            accountedStrokeCount: min(accounted, drawing.strokes.count)
        ), book: book)
    }

    private func startTicking() {
        tickTask?.cancel()
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard let self, !Task.isCancelled else { return }
                self.perform(self.machine.handle(.tick(now: Date())))
                switch self.machine.state {
                case .committed, .cancelled, .idle:
                    return
                default:
                    continue
                }
            }
        }
    }

    /// Design affordance ("press to let the ink rest"): skip the remaining
    /// rest window by feeding the machine a tick past `commitAfter`. Only
    /// meaningful while resting/speculating; a no-op otherwise.
    func commitNow() {
        tickTask?.cancel()
        perform(machine.handle(.tick(now: Date(timeIntervalSinceNow: 10))))
    }

    /// After a decline (offline, cooldown elapsed), ready the page again —
    /// and actually re-send. The page is finished, so the writer has no
    /// reason to add a stroke; a retry that only re-armed a cadence nothing
    /// would ever tick again was an inert button (audit D-6).
    func retry() {
        machine.reset()
        // The dedupe guards accidental re-sends of ink still on the page; a
        // deliberate "try again" on the very same ink is not one of those, and
        // must not land on a silently dead page.
        previousDigest = nil
        guard hasUnsentInk, !exchangeInFlight else {
            status = .idle
            return
        }
        status = .resting
        perform(machine.handle(.strokeBegan))
        perform(machine.handle(.strokeEnded(at: Date())))
        // Skip the rest window: the tap IS the decision to send.
        commitNow()
    }

    // MARK: - The typed hand (no-pencil fallback)

    /// What the keyboard has written on the page. When no pencil is about,
    /// the keys stand in for the pen: every keystroke feeds the same rest
    /// cadence as a stroke, so a pause in typing lets the page drink the
    /// words exactly like ink.
    var typedDraft = ""

    func typedDraftChanged() {
        guard machine.state != .held else {
            scheduleDraftSave()
            return
        }
        if typedDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // The draft was erased entirely; nothing waits to send.
            scheduleDraftSave()
            tickTask?.cancel()
            gateTask?.cancel()
            if canCancelSend {
                perform(machine.handle(.cancelRequested))
            } else {
                machine.reset()
            }
            status = .idle
            return
        }
        strokeBegan()
        strokeEnded()
    }

    // MARK: - Tool tray (task B5)

    /// Eraser toggle — the canvas view swaps the PKCanvasView tool; Pencil
    /// double-tap flips this too.
    var eraserOn = false

    var isHeld: Bool { machine.state == .held }

    /// True while a send is pending but uncommitted — the window where
    /// cancel is meaningful.
    var canCancelSend: Bool {
        switch machine.state {
        case .resting, .speculating: true
        default: false
        }
    }

    private var hasUnsentInk: Bool {
        (canvas?.drawing.strokes.count ?? 0) > sentStrokeCount
            || !typedDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// HOLD — "the page waits": pauses idle-send entirely. Releasing resumes
    /// the normal rest cadence when unsent ink is waiting on the page.
    func toggleHold() {
        tickTask?.cancel()
        perform(machine.handle(.holdToggled))
        if machine.state == .held {
            status = .held
        } else if hasUnsentInk {
            perform(machine.handle(.strokeBegan))
            perform(machine.handle(.strokeEnded(at: Date())))
            status = .resting
            startTicking()
        } else {
            status = .idle
        }
    }

    /// CANCEL SEND — aborts the pending (uncommitted) send; ink stays.
    func cancelSend() {
        guard canCancelSend else { return }
        tickTask?.cancel()
        gateTask?.cancel()
        perform(machine.handle(.cancelRequested))
        status = .idle
    }

    /// TURN PAGE — manual archive-and-clear to start fresh, no reply needed.
    func turnPage() {
        tickTask?.cancel()
        gateTask?.cancel()
        exchangeTask?.cancel()
        // What may pair with any ink being turned away (audit H-3): a reply
        // already filed — this exchange's, or a revisited page's — files
        // NOTHING again, or Remembered shows it twice against ink it never
        // answered; and a partial stream was never a reply at all.
        let unfiledReply = displayedEntryID == nil && !exchangeInFlight ? streamedText : ""
        // The teardown owns the flags; the cancelled task's late writes are
        // fenced out by the generation token.
        exchangeGeneration += 1
        exchangeInFlight = false
        sentDrawing = nil
        sentTypedOnly = false
        videoTask?.cancel()
        video = .none
        offer = nil
        upload.abort()
        completeExchange(filing: unfiledReply)
        streamedText = ""
        displayedEntryID = nil
        ttfsMS = nil
        developing = false
        imageURL = nil
        machine.reset()
        status = .idle
    }

    func undo() {
        canvas?.undoManager?.undo()
        resyncAfterHistoryStep()
    }

    func redo() {
        canvas?.undoManager?.redo()
        resyncAfterHistoryStep()
    }

    /// Undo and redo rewrite the page behind the send machine's back (audit
    /// M-4): a speculated snapshot goes stale the moment the strokes it
    /// pictured change, and the stroke-count delta fires events into states
    /// with no transition — settle dots that dance forever, sending nothing.
    /// Reset, then re-arm from what actually stands on the page.
    private func resyncAfterHistoryStep() {
        // The rewritten page invalidates any speculated snapshot: a commit
        // must never send strokes the writer just removed.
        upload.abort()
        // Mid-exchange the resolution owns the machine; a held page stays
        // held, absorbing the edit without arming anything.
        guard !exchangeInFlight, machine.state != .held else { return }
        tickTask?.cancel()
        machine.reset()
        if hasUnsentInk {
            // Unsent work still stands: re-arm the rest cadence from the
            // page as it now reads, exactly as if the pen had just lifted.
            perform(machine.handle(.strokeBegan))
            perform(machine.handle(.strokeEnded(at: Date())))
            status = .resting
            startTicking()
        } else {
            status = streamedText.isEmpty ? .idle : .answered
        }
    }

    // MARK: - Machine effects

    private func perform(_ effects: [SendEffect]) {
        for effect in effects {
            switch effect {
            case .beginSpeculativeUpload:
                beginSpeculativeUpload()
            case .commitSend:
                commitSend()
            case .abortUpload:
                upload.abort()
            }
        }
    }

    /// The rest mark's speculative upload: rasterize off the main actor,
    /// then open the window — but only if the rest still stands. The page
    /// may have moved on while the snapshot rendered; `SpeculativeUpload`'s
    /// generation fences late completions, and this fences late beginnings.
    private func beginSpeculativeUpload() {
        let typed = typedDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let drawing = canvas?.drawing
        Task { [weak self] in
            guard let self else { return }
            guard let payload = await self.snapshotPayload(typed: typed, drawing: drawing) else {
                return
            }
            guard case .speculating = self.machine.state else { return }
            self.upload.begin(payload)
        }
    }

    private func snapshotPayload(typed: String, drawing: PKDrawing?) async -> SnapshotPayload? {
        // The typed hand takes precedence: when the keys wrote the page, the
        // snapshot is a rendering of that text, same pipeline downstream.
        if !typed.isEmpty {
            guard let payload = TypedInkRasterizer.payload(
                text: typed, pageWidth: canvas?.bounds.width ?? 720
            ), payload.digest != previousDigest else { return nil }
            return payload
        }
        guard let drawing, let canvasBounds = canvas?.bounds else { return nil }
        // The heavy half — PKDrawing render, grayscale filter, JPEG encode —
        // runs off the main actor (audit L-8): pen-up on a full page must
        // never hitch the stroke still being drawn. The drawing is a value
        // and the rasterizer is immutable after init; copying them out is
        // the whole safety story.
        let newStrokeBounds = drawing.strokes.dropFirst(sentStrokeCount).map(\.renderBounds)
        let rasterizer = PKDrawingRasterizer(drawing: drawing)
        let previous = previousDigest
        return await Task.detached(priority: .userInitiated) { () -> SnapshotPayload? in
            let processor = SnapshotProcessor(rasterizer: rasterizer)
            let result = try? processor.process(
                newStrokeBounds: newStrokeBounds,
                canvasBounds: canvasBounds,
                previousDigest: previous
            )
            guard case .send(let payload) = result else { return nil }
            return payload
        }.value
    }

    private func commitSend() {
        // ONE send at a time (audit D-2): the canvas stays live while the
        // Book answers, so the rest cadence can commit again mid-stream —
        // and the second snapshot billed a second moment for the same page.
        // Refuse; the resolving exchange resets the machine, and the next
        // pause re-arms the cadence for whatever ink is genuinely unsent.
        guard !exchangeInFlight else {
            machine.reset()
            return
        }
        // Freeze what this exchange carries before anything suspends (audit
        // L-2): the drawing captured here is what the archive will file, so
        // a stroke or keystroke landing during the hop can neither change
        // what was gated nor be absorbed without ever being uploaded.
        let typed = typedDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let committedDrawing = canvas?.drawing
        gateTask?.cancel()
        gateTask = Task { [weak self] in
            guard let self else { return }
            // The speculated snapshot if its window is still open, or a
            // fresh rasterization — off the main actor either way.
            let payload: SnapshotPayload?
            if let speculated = self.upload.payload {
                payload = speculated
            } else {
                payload = await self.snapshotPayload(typed: typed, drawing: committedDrawing)
            }
            guard let payload else {
                self.machine.reset()
                self.status = .idle
                return
            }
            guard !Task.isCancelled else { return }
            // The tier and the day's counters both come from durable
            // accounting; the counter this replaces lived on this object,
            // which SwiftUI rebuilds on every Book switch and every
            // shelf→page round trip — so the free cap reset itself, and
            // navigating to the paywall was the reset.
            let snapshot = await self.entitlements.snapshot()
            let config = await self.entitlements.gateConfig()
            guard !Task.isCancelled else { return }
            // Gate order (must-test invariant): canSend runs to completion and
            // returns BEFORE any model call. The modality is what this
            // exchange will actually produce: a Book that develops makes an
            // image, and gating those as `.ink` made the Plus image soft cap
            // unreachable while `imagesUsedToday` kept counting (audit M-5).
            let modality: Modality = Book.by(id: self.book).develops ? .image : .ink
            switch SendGate.canSend(modality: modality, snapshot: snapshot, config: config) {
            case .paywall(let trigger):
                self.status = .paywall(trigger)
                self.machine.reset()
                self.upload.abort()
                await self.analytics.track(.paywallShown(trigger: trigger.rawValue))
            case .cooldown(let seconds):
                self.status = .cooldown(seconds)
                self.machine.reset()
                self.upload.abort()
                await self.analytics.track(.cooldownHit(seconds: seconds))
            case .allow:
                self.beginExchange(
                    payload: payload, typed: typed, drawing: committedDrawing,
                    memoryEnabled: snapshot.memoryEnabled
                )
            }
        }
    }

    private func beginExchange(
        payload: SnapshotPayload, typed: String, drawing: PKDrawing?, memoryEnabled: Bool
    ) {
        status = .sending
        streamedText = ""
        displayedEntryID = nil
        writerReclaimed = false
        sentTypedText = typed.isEmpty ? nil : typed
        // Freeze what this exchange carries (audit D-2/D-3): the committed
        // drawing — captured with the payload, before the gate hop (audit
        // L-2) — is what the archive will file, and `sentStrokeCount`
        // advances NOW — a snapshot taken while this exchange streams must
        // crop from here, not from a stale base that defeats the dedupe.
        sentBase = sentStrokeCount
        sentTypedOnly = payload.typed
        if payload.typed {
            // The typed hand wrote this exchange alone (audit M-5): the
            // snapshot pictured words, not the canvas — whatever pencil
            // strokes stand stay standing, unsent, and the accounting does
            // not move.
            sentDrawing = nil
        } else {
            sentDrawing = drawing
            sentStrokeCount = sentDrawing?.strokes.count ?? sentStrokeCount
        }
        exchangeGeneration += 1
        exchangeInFlight = true
        let generation = exchangeGeneration
        ttfsMS = nil
        developing = false
        imageURL = nil
        // A new exchange retires the previous reply's offer — the verdict
        // belongs to the reply that earned it.
        videoTask?.cancel()
        video = .none
        offer = nil
        // The dedupe was dead code: `previousDigest` was only ever assigned
        // nil, so `SnapshotResult.skipDuplicate` was unreachable and an
        // unchanged page could commit the same exchange — and the same bill —
        // twice. An explicit `retry()` clears it again.
        previousDigest = payload.digest
        // Memory, prior words and the session's last reply: all three fields
        // used to leave as their empty defaults, so the Book answered with no
        // memory of the exchange still standing on the facing page.
        let context = PageContextBuilder.context(
            book: book,
            lastTurn: lastTurn,
            memories: memory.summaries(for: book),
            memoryEnabled: memoryEnabled
        )
        let committedTicket = upload.takeCommitted()
        Task { await analytics.track(.pageSent(book: book)) }
        exchangeTask = Task { [weak self] in
            await self?.runExchange(
                payload: payload, context: context, ticket: committedTicket, generation: generation
            )
        }
    }

    private func runExchange(
        payload: SnapshotPayload, context: PageContext, ticket: UploadTicket?, generation: Int
    ) async {
        var timer = ExchangeTimer()
        var assembler = ReplyAssembler()
        var chunks: [ReplyChunk] = []
        var completed = false
        var preempted = false

        // Only the task holding the CURRENT generation may touch the page
        // (audit D-8): a cancelled task resuming out of a stuck `.sending`
        // used to map its own cancellation to `.inkRanDry` and write a
        // decline card over the fresh blank page that replaced it.
        func isCurrent() -> Bool {
            generation == exchangeGeneration && !Task.isCancelled
        }

        let stream = CrisisInterceptor.intercept(
            proxy.exchange(payload: payload, book: book, context: context, ticket: ticket)
        )
        do {
            for try await chunk in stream {
                guard isCurrent() else { return }
                chunks.append(chunk)
                if let ms = timer.markFirstChunk() {
                    ttfsMS = ms
                    status = .answering
                }
                for output in assembler.consume(chunk) {
                    switch output {
                    case .appendInk(let delta):
                        streamedText += delta
                    case .openDevelopSlot:
                        developing = true
                    case .renderImageFinal(let url):
                        // `developing` stays true — PageView keeps the frame up
                        // for the finished picture and only withdraws it when
                        // the slot closes.
                        imageURL = url
                    case .closeDevelopSlot:
                        // The develop failed server-side. The ink still stands,
                        // so the page just stops waiting for a picture.
                        developing = false
                    case .crisis(let payload):
                        preempted = true
                        status = .crisis(payload.message)
                        await analytics.track(.crisisFlow(book: book))
                    case .completed:
                        completed = true
                        // A preempted exchange is never billed and never spends
                        // a daily moment (`MomentBilling` excludes any stream
                        // carrying a crisis chunk).
                        if MomentBilling.isBillable(chunks) {
                            // An exchange that actually developed a picture
                            // ticks the image counter too — that counter is
                            // what drives the Plus soft-cap cooldown. Keyed on
                            // the arrived URL, not the develop flag: a slot
                            // that opened and failed is not an image.
                            await entitlements.record(imageURL == nil ? .ink : .image)
                        }
                        if let ttfsMS {
                            // Same key as the billing above (audit L-5): an
                            // exchange that developed a picture answered in
                            // `.image`, and the funnel must say so.
                            await analytics.track(.pageAnswered(
                                book: book, modality: imageURL == nil ? .ink : .image, ttfsMS: ttfsMS
                            ))
                        }
                    case .offerVideo(let verdict):
                        // The page may now OFFER (task J3). It does not
                        // generate, does not reserve, and does not spend —
                        // `requestVideo()` runs only from a tap.
                        offer = verdict
                        video = .offered(verdict)
                        await analytics.track(.videoOffered(book: book))
                        // What the tap would cost, so the affordance can be
                        // honest before it commits.
                        refreshWallet()
                    case .requestVideoCredit, .releaseVideoCredit:
                        releaseVideoCredit()
                    case .renderImagePreview, .playVideo:
                        break // clips arrive on the /v1/video stream, not here
                    }
                }
            }
            guard isCurrent() else { return }
            // Exchange lifecycle (dev spec §3): only a stream that reached
            // `.done` is a completed exchange. Crisis preemption keeps the
            // user's ink; a stream that fell silent is a failed send.
            if completed {
                completeExchange(filing: streamedText)
                // A hold pressed while the Book answered still stands once
                // the answer lands (audit M-1): the reply surfaces either
                // way, but the page stays held rather than quietly re-arming.
                status = machine.state == .held ? .held : .answered
            } else if preempted {
                // "Keeps the user's ink" in fact, not just in comment (audit
                // D-5): the send accounting rolls back so the standing
                // strokes read as unsent, and the draft is flushed to disk
                // before the navigation to the crisis screen tears the view
                // down. Returning to the Book finds the page as written.
                rollbackSend()
                saveDraftNow()
            } else {
                rollbackSend()
                discardDeclinedDraft()
                status = Self.declineStatus(for: .badResponse)
            }
        } catch let error as ProxyError {
            // Failed send: strokes stay on the page, fully visible — the
            // user's words never vanish into a failed exchange.
            for output in assembler.abandon() {
                if case .releaseVideoCredit = output { releaseVideoCredit() }
            }
            guard isCurrent() else { return }
            rollbackSend()
            discardDeclinedDraft()
            status = Self.declineStatus(for: error)
        } catch {
            for output in assembler.abandon() {
                if case .releaseVideoCredit = output { releaseVideoCredit() }
            }
            guard isCurrent() else { return }
            rollbackSend()
            discardDeclinedDraft()
            status = .declined("inkRanDry")
        }
        if isCurrent() {
            // The machine belongs to the writer again — unless they held the
            // page mid-stream, in which case the hold stands (audit M-1).
            if machine.state != .held { machine.reset() }
            exchangeInFlight = false
            exchangeTask = nil
            // Ink laid down while the Book answered was refused mid-stream
            // (one send at a time), so re-arm the cadence now — the tail
            // sends after the normal settle instead of sitting silently
            // unsent (audit M-2). Only a completed exchange: a failed send
            // stands behind its decline card and retries by hand, and a
            // crisis interception never re-sends anything.
            if completed, !preempted, machine.state != .held, hasUnsentInk {
                perform(machine.handle(.strokeBegan))
                perform(machine.handle(.strokeEnded(at: Date())))
                status = .resting
                startTicking()
            }
        }
    }

    /// A send that did not complete leaves its ink standing on the page —
    /// the accounting must agree, or the standing ink reads as already
    /// absorbed and `retry()` finds nothing to say (audit D-6).
    /// A send that came back declined. The ink stays standing for the length
    /// of THIS visit — "try again" needs something to retry — but it is no
    /// longer kept on disk, so leaving the Book and opening it again gives a
    /// fresh page instead of the failed one. Melih's call, twice stated: a
    /// Book must open on a new session, never on the page that failed.
    ///
    /// Cleared the moment the writer touches the page again: work they are
    /// actively rewriting is live unsent work, and that still survives a
    /// navigation the way audit D-1 intended. The crisis path is untouched —
    /// it flushes deliberately on its own branch, so a page that routed
    /// someone to real help is still there when they come back.
    private var sendDeclined = false

    /// The writer took the page back up; whatever failed before is being
    /// worked on again, so it is worth keeping once more.
    private func clearDeclinedHold() {
        guard sendDeclined else { return }
        sendDeclined = false
    }

    /// Drops the failed page from disk and stops the teardown re-writing it.
    private func discardDeclinedDraft() {
        sendDeclined = true
        draftSaveTask?.cancel()
        drafts?.clear(book: book)
    }

    private func rollbackSend() {
        sentStrokeCount = sentBase
        sentDrawing = nil
        sentTypedOnly = false
        sentTypedText = nil
        // A partial stream must not stand as the reply: `beginExchange`
        // already cleared the previous exchange, so whatever accumulated
        // here is half an answer — the reply surfaces whole or not at all.
        // The decline card stands alone; the writer's ink is what retries.
        streamedText = ""
        scheduleDraftSave()
    }

    /// The page is being torn down (audit D-4): the stream must die with it,
    /// or the server settles a moment nobody will read and the reply files
    /// nowhere — the weak canvas is already gone by completion. Cancelling
    /// propagates the disconnect, and the proxy releases instead of settling.
    func pageWillDisappear() {
        // The draft outlives the view (audit D-1) — flush before the canvas
        // reference dies with it.
        saveDraftNow()
        tickTask?.cancel()
        gateTask?.cancel()
        exchangeTask?.cancel()
        videoTask?.cancel()
        walletTask?.cancel()
        upload.abort()
    }

    /// A held clip credit goes back (task J4). The hold itself lives on the
    /// SERVER — it is reserved when a generation starts and released by the
    /// same route on every failure path, including a client that vanishes
    /// mid-generation. So the client's part is to stop asking and refresh what
    /// the wallet actually says, rather than to keep a second, drifting count.
    ///
    /// This used to be an empty stub, deliberately kept as a real arm so that
    /// wiring video could not silently strand a credit. It is now wired.
    private func releaseVideoCredit() {
        refreshWallet()
    }

    /// Re-reads the server's wallet: the client never decides what a clip
    /// costs or whether a free one remains, it only shows what it was told.
    ///
    /// Refilling the purse also revives the offer. A reader who left to buy a
    /// vial comes back to a page that is simply ready again — no second tap on
    /// a dead card, no re-writing the page to earn a new verdict.
    func refreshWallet() {
        walletTask?.cancel()
        walletTask = Task { [weak self] in
            guard let self else { return }
            let view = try? await self.proxy.wallet()
            guard !Task.isCancelled, let view else { return }
            self.wallet = view
            if case .needsVials = self.video, view.canAffordClip, let offer = self.offer {
                self.video = .offered(offer)
            }
        }
    }

    /// MAKE THIS MOVE (task J4). The one entry point into generation, and it
    /// exists only behind a tap: nothing on this object ever calls it on the
    /// reader's behalf.
    ///
    /// Flow: reserve (server) → generate → bloom → settle (server). Every
    /// failure releases, including cancellation — leaving the page or killing
    /// the app drops the stream, and the route refunds rather than charging
    /// for a clip delivered to nobody.
    func requestVideo() {
        // Guarded on the STATE (only an offer on screen may be acted on) but
        // driven by the retained verdict, so the two cannot drift.
        guard case .offered = video, let verdict = offer else { return }
        // Double-tap protection is layered: the state moves out of `.offered`
        // immediately, and the videoID makes the SERVER idempotent even if a
        // retry gets past this.
        let videoID = UUID()
        let wasFree = wallet?.nextClipIsFree ?? false
        video = .generating
        let startedAt = Date()

        videoTask?.cancel()
        videoTask = Task { [weak self] in
            guard let self else { return }
            await self.analytics.track(.videoRequested(book: self.book, free: wasFree))
            var assembler = ReplyAssembler()
            var delivered = false
            // The server's own reason for a clip that never came. Without it a
            // moderation rejection and a provider outage look identical in the
            // funnel, and those two numbers mean very different things.
            var serverFailure: String?
            do {
                for try await chunk in self.proxy.video(briefID: verdict.briefID, videoID: videoID) {
                    if case .videoFailed(let failure) = chunk {
                        serverFailure = failure.reason
                    }
                    for output in assembler.consume(chunk) {
                        switch output {
                        case .playVideo(let url):
                            delivered = true
                            self.video = .delivered(url)
                        case .releaseVideoCredit:
                            // The server already released its own hold; this
                            // refreshes what the page believes it has left.
                            self.releaseVideoCredit()
                        case .completed:
                            break
                        default:
                            break
                        }
                    }
                }
                if delivered {
                    let waited = Int(Date().timeIntervalSince(startedAt) * 1000)
                    await self.analytics.track(.videoDelivered(book: self.book, waitedMS: waited))
                    self.refreshWallet()
                } else {
                    // The stream ended without a clip: treat it as a failure
                    // so the page never waits forever on a picture that is
                    // not coming. A server-stated reason wins over the generic
                    // one — "moderated" and "the provider fell over" are the
                    // same non-event to the reader and very different to us.
                    self.failVideo(serverFailure == "moderated" ? .moderated : .badResponse)
                }
            } catch is CancellationError {
                // The reader left. The server sees the disconnect and releases;
                // the page simply stops offering to show what never arrived.
                self.video = .none
            } catch let error as ProxyError {
                guard error != .cancelled else {
                    self.video = .none
                    return
                }
                self.failVideo(error)
            } catch {
                self.failVideo(.badResponse)
            }
        }
    }

    /// No clip, and the vial came back. The reader gets the Book's line, never
    /// a provider string; the analytics get the coarse bucket (task J9).
    private func failVideo(_ error: ProxyError) {
        let line = Self.videoDeclineCopy(for: error)
        // An empty purse is not a failure of the picture — it is a purchase
        // the reader has not made yet, and the page should say so and offer
        // the way forward rather than apologising.
        video = error == .paymentRequired ? .needsVials(line) : .failed(line)
        refreshWallet()
        let reason = Self.videoFailureReason(for: error)
        Task { [analytics, book] in
            await analytics.track(.videoFailed(book: book, reason: reason))
        }
    }

    /// In-fiction copy for a clip that did not develop. The refund promise is
    /// stated plainly — it is the one thing the reader must be able to trust.
    private static func videoDeclineCopy(for error: ProxyError) -> String {
        switch DeclineMapper.map(error, surface: .video) {
        case .pageDeclines:
            "The page will not picture this one. Your vial is untouched."
        case .inkMustRest:
            "The ink must rest before it can move again. Nothing was spent."
        case .pageIsQuiet:
            "The road is dark — a moving picture cannot travel it tonight. Nothing was spent."
        case .vialsEmpty:
            "The vials are empty, and your gifted moments are spent. Nothing was charged."
        case .inkRanDry:
            "The picture would not settle. Your vial has been returned."
        case .crisisSuspect:
            // Unreachable on the video surface — the mapper reserves this for
            // ink — but the copy stays honest if that ever changes.
            "The page will not picture this one. Your vial is untouched."
        }
    }

    /// Coarse buckets only — never a provider string, never page content.
    private static func videoFailureReason(for error: ProxyError) -> String {
        switch error {
        case .moderated: "moderated"
        case .paymentRequired: "no_credit"
        case .rateLimited: "rate_limited"
        case .offline: "offline"
        case .badResponse: "no_clip"
        case .server(let status): "server_\(status)"
        case .transport: "transport"
        case .cancelled: "cancelled"
        }
    }

    /// The clip filled the screen — the Riddle-diary moment (task J9).
    func recordImmersiveOpen() {
        Task { [analytics, book] in
            await analytics.track(.videoImmersiveOpened(book: book))
        }
    }

    /// A 429 carries a cooldown the page already knows how to render.
    /// Stringifying the mapped state threw the seconds away and offered a "try
    /// again" button that re-429s immediately.
    private static func declineStatus(for error: ProxyError) -> PageStatus {
        switch DeclineMapper.map(error, surface: .ink) {
        case .inkMustRest(let seconds): .cooldown(seconds ?? 60)
        case .pageDeclines: .declined("pageDeclines")
        case .pageIsQuiet: .declined("pageIsQuiet")
        case .inkRanDry: .declined("inkRanDry")
        // Ink costs no vials, so a payment refusal on this path is a server
        // disagreement rather than an empty purse — decline in fiction and let
        // the reader try again, never send them to a shop they don't need.
        case .vialsEmpty: .declined("inkRanDry")
        // Provider moderation of the writer's own page (audit S-1): the most
        // explicit disclosures are exactly the ones the provider blocks before
        // the Book can answer, so this routes to the crisis card — real
        // resources, no retry button — never to "the spirit is distant".
        case .crisisSuspect: .crisis(Self.moderatedCrisisMessage)
        }
    }

    /// Shown when a provider block routes to the crisis card. CrisisView
    /// carries its own full copy; this string is the status's payload, kept
    /// for parity with a server-sent crisis.
    private static let moderatedCrisisMessage =
        "Let’s set the story down for a moment. Please reach out to a real person who can be with you in this."

    /// `.exchangeComplete`: archive the strokes to the page record, then
    /// REMOVE them from the live canvas — absorption ends in removal, never
    /// minimum-opacity ghosting. The canvas is ready for the next exchange.
    /// The reply to file is the caller's to name (audit H-3): the resolving
    /// stream passes what it streamed; `turnPage` passes "" when the standing
    /// reply is already archived, so no reply ever files twice.
    private func completeExchange(filing replyText: String) {
        // The typed page is absorbed the same way ink is: the draft clears
        // and the field stands empty for the next exchange — but it files to
        // the archive first, so typed exchanges are remembered like ink ones.
        let draft = typedDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let typed = sentTypedText ?? (draft.isEmpty ? nil : draft)
        let typedOnly = sentTypedOnly
        sentTypedText = nil
        sentTypedOnly = false
        typedDraft = ""
        // Archive what was SENT (audit D-3), never whatever stands on the
        // canvas at completion — a sentence written while the Book answered
        // belongs to the next exchange, not filed under this reply and wiped.
        // `turnPage` archives with no send in flight, so it falls back to the
        // canvas as it stands.
        let sent = sentDrawing
        let drawing = sent ?? canvas?.drawing ?? PKDrawing()
        // Strokes at or below the base were restored from the archive by a
        // revisit or already absorbed — turning that page unchanged must not
        // file the same exchange twice.
        let base = sent == nil ? sentStrokeCount : sentBase
        // A typed-only send never pictured the pencil strokes (audit M-5):
        // they are not this exchange's ink and must not file under its reply.
        let hasFreshInk = !typedOnly && drawing.strokes.count > base
        // ONE exchange files ONE entry carrying both hands. The two branches
        // used to run unconditionally, so a page with ink and typed words filed
        // two entries with the same reply — and since `snapshotPayload` gives
        // the typed hand absolute precedence, the ink entry claimed the Book
        // had answered strokes it never saw.
        if typed != nil || hasFreshInk {
            // Only the strokes past the base: anything below it belongs to a
            // past page, and filing it again would duplicate that page inside
            // this entry (audit H-3).
            let entryID = archive?.archive(
                book: book,
                drawing: hasFreshInk
                    ? PKDrawing(strokes: Array(drawing.strokes.dropFirst(base)))
                    : PKDrawing(),
                typedText: typed,
                replyText: replyText
            )
            displayedEntryID = entryID
            // A page filed this visit joins the session thread.
            if let entryID { sessionEntryIDs.insert(entryID) }
            lastTurn = PageContextBuilder.Turn(written: typed, reply: replyText)
        }
        sentDrawing = nil
        sentBase = 0
        guard let canvas else {
            if !typedOnly { sentStrokeCount = 0 }
            previousDigest = nil
            return
        }
        if typedOnly {
            // The typed page absorbed; the canvas was never part of it
            // (audit M-5). The strokes stand exactly as written — unsent,
            // accounting untouched — and the draft records them that way.
            previousDigest = nil
            saveDraftNow()
            return
        }
        let current = canvas.drawing
        if let sent, !Self.sentPrefixStands(in: current, sent: sent) {
            // An erase while the Book answered rewrote the stroke list the
            // count was taken from (audit L-6): dropping by count would keep
            // the wrong strokes — or wipe fresh ink outright. The page stays
            // as the writer made it, all of it unsent; the reply above still
            // filed against what was actually sent.
            sentStrokeCount = 0
            previousDigest = nil
            saveDraftNow()
            return
        }
        // Absorption removes exactly the sent strokes: a tail written while
        // the Book answered stays on the page, fully visible and still
        // unsent — never silently wiped with the absorbed exchange.
        if let sent, current.strokes.count > sent.strokes.count {
            canvas.drawing = PKDrawing(strokes: Array(current.strokes.dropFirst(sent.strokes.count)))
        } else {
            canvas.drawing = PKDrawing()
        }
        sentStrokeCount = 0
        // The digest dedupe only guards re-sends of ink still on the page;
        // once absorbed, writing the very same thing again is a new
        // utterance — a stale digest here left the page silently dead.
        previousDigest = nil
        // "Only I can bring it back": one undo step returns the absorbed
        // page to the canvas (where it behaves like freshly written ink).
        canvas.undoManager?.removeAllActions()
        canvas.undoManager?.registerUndo(withTarget: canvas) { target in
            MainActor.assumeIsolated { target.drawing = current }
        }
        // The absorbed page left the canvas; the draft follows — an empty
        // page clears the file, a kept tail persists as the new draft.
        saveDraftNow()
    }

    /// Cheap prefix identity (audit L-6): the canvas still begins with the
    /// sent strokes iff the count allows it and the LAST sent stroke sits
    /// where it did — an erase anywhere in the prefix shifts or removes it.
    /// Bounds, never a deep point compare; this runs at every completion.
    private static func sentPrefixStands(in current: PKDrawing, sent: PKDrawing) -> Bool {
        let sentCount = sent.strokes.count
        guard current.strokes.count >= sentCount else { return false }
        guard let lastSent = sent.strokes.last else { return true }
        return current.strokes[sentCount - 1].renderBounds == lastSent.renderBounds
    }
}
