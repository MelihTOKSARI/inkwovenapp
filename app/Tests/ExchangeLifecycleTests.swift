import Testing
import PencilKit
import InkCore
import InkNet
import InkAnalytics
@testable import Inkwoven

/// Exchange lifecycle (development.md §3, tasks B3): `.done` → strokes
/// archived + removed from the live canvas; any `ProxyError` → strokes
/// retained fully visible. Proxy is mocked so the success path is verified
/// before the real AI integration lands.
@MainActor
@Suite("Exchange lifecycle")
struct ExchangeLifecycleTests {
    // MARK: - Doubles

    struct ScriptedProxy: ExchangeProxying {
        var chunks: [ReplyChunk] = []
        var failure: ProxyError?

        func exchange(
            payload: SnapshotPayload, book: BookID, context: PageContext, ticket: UploadTicket?
        ) -> AsyncThrowingStream<ReplyChunk, Error> {
            AsyncThrowingStream { continuation in
                for chunk in chunks { continuation.yield(chunk) }
                continuation.finish(throwing: failure)
            }
        }

        func preupload(_ payload: SnapshotPayload) async throws -> UploadTicket {
            UploadTicket(id: "test-ticket", expiresAt: .distantFuture)
        }

        func abort(_ ticket: UploadTicket) async {}
    }

    @MainActor
    final class RecordingArchive: PageArchiving {
        var archived: [(book: BookID, strokes: Int, typedText: String?, replyText: String)] = []

        @discardableResult
        func archive(book: BookID, drawing: PKDrawing, typedText: String?, replyText: String) -> UUID {
            archived.append((book, drawing.strokes.count, typedText, replyText))
            return UUID()
        }
    }

    struct SilentSink: AnalyticsSink {
        func track(name: String, parameters: [String: AnalyticsValue]) {}
    }

    // MARK: - Fixtures

    private func canvasWithOneStroke() -> PKCanvasView {
        let canvas = PKCanvasView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        let points = (0..<8).map { i in
            PKStrokePoint(
                location: CGPoint(x: 120 + CGFloat(i) * 14, y: 220),
                timeOffset: Double(i) * 0.02,
                size: CGSize(width: 4, height: 4),
                opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2
            )
        }
        let path = PKStrokePath(controlPoints: points, creationDate: .now)
        canvas.drawing = PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: .black), path: path)])
        return canvas
    }

    private func makeInteractor(
        proxy: ScriptedProxy, archive: RecordingArchive, canvas: PKCanvasView
    ) -> PageInteractor {
        let interactor = PageInteractor(
            proxy: proxy,
            analytics: Analytics(sink: SilentSink()),
            book: .oracle,
            archive: archive,
            // Ephemeral: the live default is durable and process-wide, so a
            // test run would otherwise spend the host's real daily allowance
            // and start paywalling itself.
            entitlements: .ephemeral()
        )
        interactor.attach(canvas: canvas)
        return interactor
    }

    /// Drives rest past the commit threshold and waits for the exchange task
    /// to resolve into a terminal status.
    private func sendAndSettle(_ interactor: PageInteractor) async throws {
        interactor.strokeBegan()
        interactor.strokeEnded()
        interactor.commitNow()
        for _ in 0..<200 {
            switch interactor.status {
            case .answered, .declined, .crisis, .cooldown, .paywall:
                return
            default:
                try await Task.sleep(for: .milliseconds(25))
            }
        }
        Issue.record("exchange never settled; status: \(interactor.status)")
    }

    // MARK: - Tests

    @Test("success: .done archives the strokes and removes them from the live canvas")
    func successArchivesAndClears() async throws {
        let canvas = canvasWithOneStroke()
        let archive = RecordingArchive()
        let proxy = ScriptedProxy(chunks: [
            .inkDelta("The page drinks your ink, and answers."),
            .done(Usage(modelID: "echo", inputTokens: 1, outputTokens: 8)),
        ])
        let interactor = makeInteractor(proxy: proxy, archive: archive, canvas: canvas)

        try await sendAndSettle(interactor)

        #expect(interactor.status == .answered)
        #expect(canvas.drawing.strokes.isEmpty, "zero user strokes may remain at any opacity")
        #expect(archive.archived.count == 1)
        #expect(archive.archived.first?.strokes == 1)
        #expect(archive.archived.first?.replyText == "The page drinks your ink, and answers.")
    }

    @Test("failure: a ProxyError retains the strokes and archives nothing")
    func failureRetainsInk() async throws {
        let canvas = canvasWithOneStroke()
        let archive = RecordingArchive()
        let proxy = ScriptedProxy(chunks: [], failure: .offline)
        let interactor = makeInteractor(proxy: proxy, archive: archive, canvas: canvas)

        try await sendAndSettle(interactor)

        guard case .declined = interactor.status else {
            Issue.record("expected .declined, got \(interactor.status)")
            return
        }
        #expect(canvas.drawing.strokes.count == 1, "the user's words never vanish into a failed send")
        #expect(archive.archived.isEmpty)
    }

    @Test("failure mid-stream: partial ink then an error still retains the strokes")
    func midStreamFailureRetainsInk() async throws {
        let canvas = canvasWithOneStroke()
        let archive = RecordingArchive()
        let proxy = ScriptedProxy(chunks: [.inkDelta("The page begins—")], failure: .transport("reset"))
        let interactor = makeInteractor(proxy: proxy, archive: archive, canvas: canvas)

        try await sendAndSettle(interactor)

        guard case .declined = interactor.status else {
            Issue.record("expected .declined, got \(interactor.status)")
            return
        }
        #expect(canvas.drawing.strokes.count == 1)
        #expect(archive.archived.isEmpty)
    }

    @Test("a stream that falls silent without .done is a failed send — ink retained")
    func silentStreamIsFailure() async throws {
        let canvas = canvasWithOneStroke()
        let archive = RecordingArchive()
        let proxy = ScriptedProxy(chunks: [.inkDelta("half a thought")], failure: nil)
        let interactor = makeInteractor(proxy: proxy, archive: archive, canvas: canvas)

        try await sendAndSettle(interactor)

        guard case .declined = interactor.status else {
            Issue.record("expected .declined, got \(interactor.status)")
            return
        }
        #expect(canvas.drawing.strokes.count == 1)
        #expect(archive.archived.isEmpty)
    }
}
