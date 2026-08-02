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
    }

    private(set) var video: VideoState = .none
    /// What a tap would spend, as the server last reported it. Nil until the
    /// wallet is read — the affordance simply says less until then, and the
    /// server decides for real either way.
    private(set) var wallet: WalletView?

    private let proxy: any ExchangeProxying
    private let analytics: Analytics
    private let book: BookID
    private let archive: (any PageArchiving)?
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
        entitlements: PageEntitlements = LiveCommerce.page,
        memory: any MemoryProviding = EmptyMemoryProvider()
    ) {
        self.proxy = proxy
        self.analytics = analytics
        self.book = book
        self.archive = archive
        self.entitlements = entitlements
        self.memory = memory
    }

    func attach(canvas: PKCanvasView) {
        self.canvas = canvas
        if let drawing = pendingRestore {
            pendingRestore = nil
            restore(drawing)
        }
    }

    // MARK: - Revisiting a remembered page

    /// A remembered exchange waiting for the canvas to attach — revisit can
    /// arrive before the page's PKCanvasView exists.
    private var pendingRestore: PKDrawing?

    /// REMEMBERED — reopen an archived exchange on the page: the user's ink
    /// returns to the canvas and the Book's reply stands on the right page,
    /// exactly as the exchange ended. The restored ink already belongs to its
    /// archived exchange, so nothing re-sends and nothing re-archives; fresh
    /// strokes on top of it start a new exchange as usual.
    func revisit(drawing: PKDrawing, replyText: String, entryID: UUID? = nil) {
        tickTask?.cancel()
        gateTask?.cancel()
        exchangeTask?.cancel()
        // A generation in flight belongs to the exchange being left; cancelling
        // is what tells the server to release its hold.
        videoTask?.cancel()
        video = .none
        upload.abort()
        machine.reset()
        typedDraft = ""
        streamedText = replyText
        displayedEntryID = entryID
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
    }

    // MARK: - Stroke events from the canvas

    func strokeBegan() {
        tickTask?.cancel()
        perform(machine.handle(.strokeBegan))
        if status == .idle || status == .resting { status = .inking }
    }

    func strokeEnded() {
        perform(machine.handle(.strokeEnded(at: Date())))
        // A held page absorbs stroke events without arming the send timer.
        guard machine.state != .held else { return }
        status = .resting
        startTicking()
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

    /// After a decline (offline, cooldown elapsed), ready the page again.
    func retry() {
        machine.reset()
        // The dedupe guards accidental re-sends of ink still on the page; a
        // deliberate "try again" on the very same ink is not one of those, and
        // must not land on a silently dead page.
        previousDigest = nil
        status = .idle
    }

    // MARK: - The typed hand (no-pencil fallback)

    /// What the keyboard has written on the page. When no pencil is about,
    /// the keys stand in for the pen: every keystroke feeds the same rest
    /// cadence as a stroke, so a pause in typing lets the page drink the
    /// words exactly like ink.
    var typedDraft = ""

    func typedDraftChanged() {
        guard machine.state != .held else { return }
        if typedDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // The draft was erased entirely; nothing waits to send.
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
        videoTask?.cancel()
        video = .none
        upload.abort()
        completeExchange()
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
    }

    func redo() {
        canvas?.undoManager?.redo()
    }

    // MARK: - Machine effects

    private func perform(_ effects: [SendEffect]) {
        for effect in effects {
            switch effect {
            case .beginSpeculativeUpload:
                if let payload = snapshotPayload() { upload.begin(payload) }
            case .commitSend:
                commitSend()
            case .abortUpload:
                upload.abort()
            }
        }
    }

    private func snapshotPayload() -> SnapshotPayload? {
        // The typed hand takes precedence: when the keys wrote the page, the
        // snapshot is a rendering of that text, same pipeline downstream.
        let typed = typedDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !typed.isEmpty {
            guard let payload = TypedInkRasterizer.payload(
                text: typed, pageWidth: canvas?.bounds.width ?? 720
            ), payload.digest != previousDigest else { return nil }
            return payload
        }
        guard let drawing = canvas?.drawing, let canvasBounds = canvas?.bounds else { return nil }
        let newStrokes = drawing.strokes.dropFirst(sentStrokeCount)
        let processor = SnapshotProcessor(rasterizer: PKDrawingRasterizer(drawing: drawing))
        let result = try? processor.process(
            newStrokeBounds: newStrokes.map(\.renderBounds),
            canvasBounds: canvasBounds,
            previousDigest: previousDigest
        )
        guard case .send(let payload) = result else { return nil }
        return payload
    }

    private func commitSend() {
        guard let payload = upload.payload ?? snapshotPayload() else {
            machine.reset()
            status = .idle
            return
        }
        // Freeze what this exchange carries before the gate suspends, so a
        // keystroke landing during the hop cannot change what was gated.
        let typed = typedDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        gateTask?.cancel()
        gateTask = Task { [weak self] in
            guard let self else { return }
            // The tier and the day's counters both come from durable
            // accounting; the counter this replaces lived on this object,
            // which SwiftUI rebuilds on every Book switch and every
            // shelf→page round trip — so the free cap reset itself, and
            // navigating to the paywall was the reset.
            let snapshot = await self.entitlements.snapshot()
            guard !Task.isCancelled else { return }
            // Gate order (must-test invariant): canSend runs to completion and
            // returns BEFORE any model call.
            switch SendGate.canSend(modality: .ink, snapshot: snapshot) {
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
                    payload: payload, typed: typed, memoryEnabled: snapshot.memoryEnabled
                )
            }
        }
    }

    private func beginExchange(payload: SnapshotPayload, typed: String, memoryEnabled: Bool) {
        status = .sending
        streamedText = ""
        displayedEntryID = nil
        sentTypedText = typed.isEmpty ? nil : typed
        ttfsMS = nil
        developing = false
        imageURL = nil
        // A new exchange retires the previous reply's offer — the verdict
        // belongs to the reply that earned it.
        videoTask?.cancel()
        video = .none
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
            await self?.runExchange(payload: payload, context: context, ticket: committedTicket)
        }
    }

    private func runExchange(
        payload: SnapshotPayload, context: PageContext, ticket: UploadTicket?
    ) async {
        var timer = ExchangeTimer()
        var assembler = ReplyAssembler()
        var chunks: [ReplyChunk] = []
        var completed = false
        var preempted = false

        let stream = CrisisInterceptor.intercept(
            proxy.exchange(payload: payload, book: book, context: context, ticket: ticket)
        )
        do {
            for try await chunk in stream {
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
                            await analytics.track(.pageAnswered(book: book, modality: .ink, ttfsMS: ttfsMS))
                        }
                    case .offerVideo(let verdict):
                        // The page may now OFFER (task J3). It does not
                        // generate, does not reserve, and does not spend —
                        // `requestVideo()` runs only from a tap.
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
            // Exchange lifecycle (dev spec §3): only a stream that reached
            // `.done` is a completed exchange. Crisis preemption keeps the
            // user's ink; a stream that fell silent is a failed send.
            if completed {
                completeExchange()
                status = .answered
            } else if !preempted {
                status = Self.declineStatus(for: .badResponse)
            }
        } catch let error as ProxyError {
            // Failed send: strokes stay on the page, fully visible — the
            // user's words never vanish into a failed exchange.
            for output in assembler.abandon() {
                if case .releaseVideoCredit = output { releaseVideoCredit() }
            }
            status = Self.declineStatus(for: error)
        } catch {
            for output in assembler.abandon() {
                if case .releaseVideoCredit = output { releaseVideoCredit() }
            }
            status = .declined("inkRanDry")
        }
        machine.reset()
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
    func refreshWallet() {
        walletTask?.cancel()
        walletTask = Task { [weak self] in
            guard let self else { return }
            let view = try? await self.proxy.wallet()
            guard !Task.isCancelled, let view else { return }
            self.wallet = view
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
        guard case .offered(let verdict) = video else { return }
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
            do {
                for try await chunk in self.proxy.video(briefID: verdict.briefID, videoID: videoID) {
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
                    // not coming.
                    self.failVideo(.badResponse)
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
        video = .failed(Self.videoDeclineCopy(for: error))
        refreshWallet()
        let reason = Self.videoFailureReason(for: error)
        Task { [analytics, book] in
            await analytics.track(.videoFailed(book: book, reason: reason))
        }
    }

    /// In-fiction copy for a clip that did not develop. The refund promise is
    /// stated plainly — it is the one thing the reader must be able to trust.
    private static func videoDeclineCopy(for error: ProxyError) -> String {
        switch DeclineMapper.map(error) {
        case .pageDeclines:
            "The page will not picture this one. Your vial is untouched."
        case .inkMustRest:
            "The ink must rest before it can move again. Nothing was spent."
        case .pageIsQuiet:
            "The road is dark — a moving picture cannot travel it tonight. Nothing was spent."
        case .vialsEmpty:
            "The vials are empty. Nothing was spent."
        case .inkRanDry:
            "The picture would not settle. Your vial has been returned."
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
        switch DeclineMapper.map(error) {
        case .inkMustRest(let seconds): .cooldown(seconds ?? 60)
        case .pageDeclines: .declined("pageDeclines")
        case .pageIsQuiet: .declined("pageIsQuiet")
        case .inkRanDry: .declined("inkRanDry")
        }
    }

    /// `.exchangeComplete`: archive the strokes to the page record, then
    /// REMOVE them from the live canvas — absorption ends in removal, never
    /// minimum-opacity ghosting. The canvas is ready for the next exchange.
    private func completeExchange() {
        // The typed page is absorbed the same way ink is: the draft clears
        // and the field stands empty for the next exchange — but it files to
        // the archive first, so typed exchanges are remembered like ink ones.
        let draft = typedDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let typed = sentTypedText ?? (draft.isEmpty ? nil : draft)
        sentTypedText = nil
        typedDraft = ""
        let drawing = canvas?.drawing ?? PKDrawing()
        // Strokes at or below `sentStrokeCount` were restored from the
        // archive by a revisit — turning that page unchanged must not file
        // the same exchange twice.
        let hasFreshInk = drawing.strokes.count > sentStrokeCount
        // ONE exchange files ONE entry carrying both hands. The two branches
        // used to run unconditionally, so a page with ink and typed words filed
        // two entries with the same reply — and since `snapshotPayload` gives
        // the typed hand absolute precedence, the ink entry claimed the Book
        // had answered strokes it never saw.
        if typed != nil || hasFreshInk {
            displayedEntryID = archive?.archive(
                book: book,
                drawing: hasFreshInk ? drawing : PKDrawing(),
                typedText: typed,
                replyText: streamedText
            )
            lastTurn = PageContextBuilder.Turn(written: typed, reply: streamedText)
        }
        guard let canvas else { return }
        canvas.drawing = PKDrawing()
        sentStrokeCount = 0
        // The digest dedupe only guards re-sends of ink still on the page;
        // once absorbed, writing the very same thing again is a new
        // utterance — a stale digest here left the page silently dead.
        previousDigest = nil
        // "Only I can bring it back": one undo step returns the absorbed
        // page to the canvas (where it behaves like freshly written ink).
        canvas.undoManager?.removeAllActions()
        canvas.undoManager?.registerUndo(withTarget: canvas) { target in
            MainActor.assumeIsolated { target.drawing = drawing }
        }
    }
}
