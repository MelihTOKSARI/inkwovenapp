import Foundation
import PencilKit
import InkCore
import InkNet
import InkMoney
import InkSafety
import InkAnalytics

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
        case paywall(PaywallTrigger)
        case declined(String)
        case crisis(String)
    }

    private(set) var status: PageStatus = .idle
    private(set) var streamedText = ""
    private(set) var ttfsMS: Int?

    private let proxy: ProxyClient
    private let analytics: Analytics
    private let book: BookID

    private var machine = IdleSendMachine()
    private weak var canvas: PKCanvasView?
    private var tickTask: Task<Void, Never>?
    private var exchangeTask: Task<Void, Never>?

    private var speculativePayload: SnapshotPayload?
    private var ticket: UploadTicket?
    private var sentStrokeCount = 0
    private var previousDigest: String?
    // Harness-local moment counter; production reconciles from the proxy.
    private var momentsUsedToday = 0

    init(proxy: ProxyClient, analytics: Analytics, book: BookID = .oracle) {
        self.proxy = proxy
        self.analytics = analytics
        self.book = book
    }

    func attach(canvas: PKCanvasView) {
        self.canvas = canvas
    }

    // MARK: - Stroke events from the canvas

    func strokeBegan() {
        tickTask?.cancel()
        perform(machine.handle(.strokeBegan))
        if status == .idle || status == .resting { status = .inking }
    }

    func strokeEnded() {
        perform(machine.handle(.strokeEnded(at: Date())))
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

    // MARK: - Machine effects

    private func perform(_ effects: [SendEffect]) {
        for effect in effects {
            switch effect {
            case .beginSpeculativeUpload:
                beginSpeculativeUpload()
            case .commitSend:
                commitSend()
            case .abortUpload:
                abortUpload()
            }
        }
    }

    private func snapshotPayload() -> SnapshotPayload? {
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

    private func beginSpeculativeUpload() {
        guard let payload = snapshotPayload() else { return }
        speculativePayload = payload
        perform(machine.handle(.uploadStarted))
        Task {
            // Network cost pre-paid at ~2s; the server never bills an
            // uncommitted ticket.
            ticket = try? await proxy.preupload(payload)
            perform(machine.handle(.uploadFinished))
        }
    }

    private func abortUpload() {
        speculativePayload = nil
        guard let ticket else { return }
        self.ticket = nil
        Task { await proxy.abort(ticket) }
    }

    private func commitSend() {
        guard let payload = speculativePayload ?? snapshotPayload() else {
            machine.reset()
            status = .idle
            return
        }

        // Gate order: canSend runs BEFORE any model call.
        let snapshot = EntitlementSnapshot(tier: .free, momentsUsedToday: momentsUsedToday)
        switch SendGate.canSend(modality: .ink, snapshot: snapshot) {
        case .paywall(let trigger):
            status = .paywall(trigger)
            Task { await analytics.track(.paywallShown(trigger: trigger.rawValue)) }
            machine.reset()
            return
        case .cooldown(let seconds):
            status = .declined("the ink must rest (\(Int(seconds))s)")
            Task { await analytics.track(.cooldownHit(seconds: seconds)) }
            machine.reset()
            return
        case .allow:
            break
        }

        status = .sending
        streamedText = ""
        ttfsMS = nil
        Task { await analytics.track(.pageSent(book: book)) }

        let committedTicket = ticket
        ticket = nil
        speculativePayload = nil
        exchangeTask = Task { [weak self] in
            await self?.runExchange(payload: payload, ticket: committedTicket)
        }
    }

    private func runExchange(payload: SnapshotPayload, ticket: UploadTicket?) async {
        var timer = ExchangeTimer()
        var assembler = ReplyAssembler()
        var chunks: [ReplyChunk] = []

        let stream = CrisisInterceptor.intercept(
            proxy.exchange(payload: payload, book: book, context: PageContext(), ticket: ticket)
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
                    case .crisis(let payload):
                        status = .crisis(payload.message)
                        await analytics.track(.crisisFlow(book: book))
                    case .completed:
                        status = .answered
                        if MomentBilling.isBillable(chunks) {
                            momentsUsedToday += 1
                        }
                        if let ttfsMS {
                            await analytics.track(.pageAnswered(book: book, modality: .ink, ttfsMS: ttfsMS))
                        }
                    default:
                        break // image/video renderers bind in the design pass
                    }
                }
            }
            previousDigest = payload.digest
            sentStrokeCount = canvas?.drawing.strokes.count ?? sentStrokeCount
        } catch let error as ProxyError {
            status = .declined(String(describing: DeclineMapper.map(error)))
        } catch {
            status = .declined("ink ran dry")
        }
        machine.reset()
    }
}
