import Testing
import Foundation
import PencilKit
import InkCore
import InkNet
import InkMoney
import InkAnalytics
@testable import Inkwoven

/// The commerce invariants the room's copy promises and the App Store requires:
/// the free daily cap is durable, entitlement comes from a verified receipt and
/// nothing else, and a crisis exchange costs the user nothing.
@MainActor
@Suite("Commerce and the daily cap")
struct CommerceTests {
    // MARK: - Doubles

    struct ScriptedProxy: ExchangeProxying {
        var chunks: [ReplyChunk] = [
            .inkDelta("The page answers."),
            .done(Usage(modelID: "echo", inputTokens: 1, outputTokens: 1)),
        ]

        func exchange(
            payload: SnapshotPayload, book: BookID, context: PageContext, ticket: UploadTicket?
        ) -> AsyncThrowingStream<ReplyChunk, Error> {
            AsyncThrowingStream { continuation in
                for chunk in chunks { continuation.yield(chunk) }
                continuation.finish()
            }
        }

        func preupload(_ payload: SnapshotPayload) async throws -> UploadTicket {
            UploadTicket(id: "t", expiresAt: .distantFuture)
        }

        func abort(_ ticket: UploadTicket) async {}
    }

    struct SilentSink: AnalyticsSink {
        func track(name: String, parameters: [String: AnalyticsValue]) {}
    }

    // MARK: - Fixtures

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

    /// One exchange on a freshly built page, exactly as SwiftUI builds it after
    /// a shelf round trip or a Book switch.
    private func sendOnFreshPage(
        book: BookID, entitlements: PageEntitlements, proxy: ScriptedProxy = ScriptedProxy()
    ) async throws -> PageInteractor.PageStatus {
        let canvas = PKCanvasView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        let interactor = PageInteractor(
            proxy: proxy,
            analytics: Analytics(sink: SilentSink()),
            book: book,
            entitlements: entitlements
        )
        interactor.attach(canvas: canvas)
        canvas.drawing = PKDrawing(strokes: [stroke()])
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

    // MARK: - The daily cap

    @Test("the free daily cap survives page re-entry and a Book switch")
    func capSurvivesRebuild() async throws {
        let entitlements = PageEntitlements.ephemeral()
        // The day's five free moments, already spent.
        for _ in 0..<5 { await entitlements.record(.ink) }

        // Backing out to the shelf and reopening the Book destroys the
        // interactor and its @State; the counter used to die with it.
        let reopened = try await sendOnFreshPage(book: .oracle, entitlements: entitlements)
        #expect(reopened == .paywall(.moments), "re-entering the page must not hand back the cap")

        // Switching Books rebuilds it again, under a different id.
        let switched = try await sendOnFreshPage(book: .keeper, entitlements: entitlements)
        #expect(switched == .paywall(.moments), "the cap is per user per day, not per Book")
    }

    @Test("a completed exchange spends exactly one moment")
    func completedExchangeSpendsOne() async throws {
        let entitlements = PageEntitlements.ephemeral()
        let outcome = try await sendOnFreshPage(book: .oracle, entitlements: entitlements)
        #expect(outcome == .answered)
        let usage = await entitlements.usage.currentUsage(at: Date())
        #expect(usage.momentsUsed == 1)
    }

    @Test("a crisis exchange spends no moment")
    func crisisIsNeverBilled() async throws {
        let entitlements = PageEntitlements.ephemeral()
        let proxy = ScriptedProxy(chunks: [
            .crisis(CrisisPayload(message: "Please talk to someone.", resources: [])),
            .done(Usage(modelID: "echo", inputTokens: 1, outputTokens: 1)),
        ])
        let outcome = try await sendOnFreshPage(
            book: .keeper, entitlements: entitlements, proxy: proxy
        )
        guard case .crisis = outcome else {
            Issue.record("expected .crisis, got \(outcome)")
            return
        }
        let usage = await entitlements.usage.currentUsage(at: Date())
        #expect(usage.momentsUsed == 0, "the page never charges for a moment that did not arrive")
    }

    @Test("the day's counters survive a cold launch")
    func usageSurvivesRelaunch() async {
        let storage = EphemeralDailyUsageStorage()
        let launch = DailyUsageStore(storage: storage)
        await launch.record(.ink)
        await launch.record(.image)

        // A second store over the same storage is what the next launch builds.
        let relaunch = DailyUsageStore(storage: storage)
        let usage = await relaunch.currentUsage(at: Date())
        #expect(usage.momentsUsed == 2)
        #expect(usage.imagesUsed == 1, "images tick the counter the Plus soft cap reads")
    }

    @Test("winding the device clock back cannot reset a spent cap")
    func clockRollbackDoesNotRefund() async {
        let store = DailyUsageStore(storage: EphemeralDailyUsageStorage())
        let now = Date()
        await store.record(.ink, at: now)
        let yesterday = now.addingTimeInterval(-60 * 60 * 24)
        let usage = await store.currentUsage(at: yesterday)
        #expect(usage.momentsUsed == 1)
    }

    // MARK: - Entitlement

    @Test("pressing the seal grants nothing without a verified purchase")
    func bindGrantsNothingWithoutAPurchase() async throws {
        let suite = UserDefaults(suiteName: "ink.tests.\(UUID().uuidString)")!
        let model = AppModel(defaults: suite, purchases: UnboundPurchaseService())
        #expect(model.bound == false)

        model.confirmBind()
        for _ in 0..<80 where model.purchaseState == .purchasing {
            try await Task.sleep(for: .milliseconds(25))
        }

        #expect(model.bound == false, "entitlement may only follow a verified receipt")
        #expect(model.screen != .memory, "an unbought binding must not open the Plus room")
        guard case .failed = model.purchaseState else {
            Issue.record("expected a failed purchase, got \(model.purchaseState)")
            return
        }
    }

    @Test("a forged ink.bound preference no longer grants Plus")
    func persistedBoundIsIgnored() {
        let suite = UserDefaults(suiteName: "ink.tests.\(UUID().uuidString)")!
        suite.set(true, forKey: "ink.bound")
        let model = AppModel(defaults: suite, purchases: UnboundPurchaseService())
        #expect(model.bound == false)
        #expect(suite.object(forKey: "ink.bound") == nil, "the stale flag is cleared, not left to be revived")
    }

    @Test("a poisoned ink.inkColor falls back instead of trapping in init")
    func negativeInkColorDoesNotTrap() {
        let suite = UserDefaults(suiteName: "ink.tests.\(UUID().uuidString)")!
        suite.set(-1, forKey: "ink.inkColor")
        let model = AppModel(defaults: suite, purchases: UnboundPurchaseService())
        #expect(model.inkColorHex == 0x2E2418)
    }

    // MARK: - What reaches the wire

    @Test("the page's context carries the last reply and honors a torn-out memory")
    func contextCarriesMemoryAndSession() {
        let memories = [
            MemorySummary(bookID: .oracle, summary: "kept", updatedAt: Date()),
            MemorySummary(bookID: .oracle, summary: "torn", updatedAt: Date(), tornOut: true),
            MemorySummary(bookID: .keeper, summary: "another Book", updatedAt: Date()),
        ]
        let context = PageContextBuilder.context(
            book: .oracle,
            lastTurn: PageContextBuilder.Turn(written: "will the harvest hold?", reply: "It holds."),
            memories: memories,
            memoryEnabled: true
        )
        #expect(context.memorySummaries == ["kept"], "a torn-out memory never leaves the device")
        #expect(context.priorInkText == "will the harvest hold?")
        #expect(context.sessionSummary?.contains("It holds.") == true)
    }

    @Test("memory stays on the device entirely for a free notebook")
    func freeNotebookSendsNoMemory() {
        let context = PageContextBuilder.context(
            book: .oracle,
            lastTurn: nil,
            memories: [MemorySummary(bookID: .oracle, summary: "kept", updatedAt: Date())],
            memoryEnabled: false
        )
        #expect(context.memorySummaries.isEmpty)
        #expect(context.sessionSummary == nil)
    }
}
