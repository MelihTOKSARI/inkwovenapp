import Testing
import PencilKit
import InkCore
import InkNet
import InkAnalytics
@testable import Inkwoven

/// Repro: writing the same ink again after a successful exchange must send
/// again — the digest dedupe may only ever skip within one page of retained
/// strokes, never across a cleared canvas.
@MainActor
@Suite("Repeat exchange after clear")
struct RepeatExchangeTests {
    struct ScriptedProxy: ExchangeProxying {
        func exchange(
            payload: SnapshotPayload, book: BookID, context: PageContext, ticket: UploadTicket?
        ) -> AsyncThrowingStream<ReplyChunk, Error> {
            AsyncThrowingStream { continuation in
                continuation.yield(.inkDelta("answered"))
                continuation.yield(.done(Usage(modelID: "echo", inputTokens: 1, outputTokens: 1)))
                continuation.finish()
            }
        }

        func preupload(_ payload: SnapshotPayload) async throws -> UploadTicket {
            UploadTicket(id: "t", expiresAt: .distantFuture)
        }

        func abort(_ ticket: UploadTicket) async {}

        // These tests script the ink exchange only; the video path (Epic J) is
        // exercised on the page itself. Asking for a clip here is a no-op that
        // yields nothing rather than a fabricated success.
        func video(briefID: String, videoID: UUID) -> AsyncThrowingStream<ReplyChunk, Error> {
            AsyncThrowingStream { $0.finish() }
        }

        func wallet() async throws -> WalletView {
            WalletView(balance: 0, available: 0, freeClipsRemaining: 0, freeClipsOpen: false)
        }
    }

    struct SilentSink: AnalyticsSink {
        func track(name: String, parameters: [String: AnalyticsValue]) {}
    }

    private func stroke() -> PKStroke {
        let points = (0..<8).map { i in
            PKStrokePoint(
                location: CGPoint(x: 120 + CGFloat(i) * 14, y: 220),
                timeOffset: Double(i) * 0.02,
                size: CGSize(width: 4, height: 4),
                opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2
            )
        }
        return PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: points, creationDate: .now))
    }

    private func settle(_ interactor: PageInteractor) async throws -> PageInteractor.PageStatus {
        interactor.strokeBegan()
        interactor.strokeEnded()
        interactor.commitNow()
        for _ in 0..<200 {
            switch interactor.status {
            case .answered, .declined, .crisis, .cooldown, .paywall:
                return interactor.status
            default:
                try await Task.sleep(for: .milliseconds(25))
            }
        }
        return interactor.status
    }

    @Test("identical ink after a cleared exchange sends again — never a silent dead page")
    func identicalInkSendsAgain() async throws {
        let canvas = PKCanvasView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        let interactor = PageInteractor(
            proxy: ScriptedProxy(), analytics: Analytics(sink: SilentSink()), book: .oracle,
            entitlements: .ephemeral()
        )
        interactor.attach(canvas: canvas)

        // First exchange.
        canvas.drawing = PKDrawing(strokes: [stroke()])
        let first = try await settle(interactor)
        #expect(first == .answered)
        #expect(canvas.drawing.strokes.isEmpty)

        // The user writes the very same thing in the very same place.
        canvas.drawing = PKDrawing(strokes: [stroke()])
        let second = try await settle(interactor)
        #expect(second == .answered, "identical re-written ink must go puff again, got \(second)")
        #expect(canvas.drawing.strokes.isEmpty, "second exchange must clear the canvas too")
    }

    @Test("undo brings the absorbed page back — the tool tray's promise")
    func undoRestoresAbsorbedInk() async throws {
        let canvas = PKCanvasView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        // undoManager resolves through the responder chain, so the canvas
        // needs a window in the hosted test.
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        window.addSubview(canvas)
        window.makeKeyAndVisible()

        let interactor = PageInteractor(
            proxy: ScriptedProxy(), analytics: Analytics(sink: SilentSink()), book: .oracle,
            entitlements: .ephemeral()
        )
        interactor.attach(canvas: canvas)

        canvas.drawing = PKDrawing(strokes: [stroke()])
        let outcome = try await settle(interactor)
        #expect(outcome == .answered)
        #expect(canvas.drawing.strokes.isEmpty)

        interactor.undo()
        #expect(canvas.drawing.strokes.count == 1, "one undo step should return the absorbed ink")
    }
}
