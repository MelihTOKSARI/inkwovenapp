import Testing
import Foundation
import CoreGraphics
@testable import Inkwoven
import InkCore
import InkNet
import InkAnalytics

/// Report-a-reply (guideline 1.2, tasks F7): the sheet's decisions without
/// standing up a view — a reason gates the send, the payload carries exactly
/// the page under report, the Keeper gets the stronger consent line, and a
/// failed send keeps the sheet open with the same reportID armed for retry.
@Suite("Report a reply")
@MainActor
struct ReportTests {
    // MARK: - Doubles

    final class RecordingSubmitter: ReportSubmitting, @unchecked Sendable {
        var attempts: [ReportPayload] = []
        var failure: ProxyError?

        func report(_ payload: ReportPayload) async throws {
            attempts.append(payload)
            if let failure { throw failure }
        }
    }

    struct FixedSnapshotter: ReportSnapshotting {
        func snapshot(strokeData: Data, typedText: String?) throws -> SnapshotPayload {
            SnapshotPayload(
                imageData: Data("report-snapshot".utf8),
                digest: String(repeating: "ab", count: 32),
                cropRect: .zero,
                pixelSize: CGSize(width: 1, height: 1)
            )
        }
    }

    final class RecordingSink: AnalyticsSink, @unchecked Sendable {
        var events: [(name: String, parameters: [String: AnalyticsValue])] = []

        func track(name: String, parameters: [String: AnalyticsValue]) {
            events.append((name, parameters))
        }
    }

    struct SilentSink: AnalyticsSink {
        func track(name: String, parameters: [String: AnalyticsValue]) {}
    }

    // MARK: - Fixtures

    private func entry(book: BookID = .oracle) -> PageArchive.Entry {
        PageArchive.Entry(
            id: UUID(),
            bookID: book.rawValue,
            createdAt: Date(timeIntervalSince1970: 1_750_000_000),
            strokeData: Data(),
            typedText: "what the writer asked",
            replyText: "The reply under report."
        )
    }

    private func model(
        entry: PageArchive.Entry,
        book: Book = .by(id: .oracle),
        submitter: RecordingSubmitter = RecordingSubmitter(),
        sink: any AnalyticsSink = SilentSink()
    ) -> ReportModel {
        ReportModel(
            entry: entry,
            book: book,
            submitter: submitter,
            analytics: Analytics(sink: sink),
            snapshotter: FixedSnapshotter()
        )
    }

    // MARK: - Tests

    @Test("a reason is required before anything can send")
    func reasonGatesTheSend() async {
        let submitter = RecordingSubmitter()
        let report = model(entry: entry(), submitter: submitter)
        #expect(!report.canSend, "no reason, no send")

        await report.send()
        #expect(submitter.attempts.isEmpty, "a guarded send must not transmit")
        #expect(report.phase == .composing)

        report.reason = .disturbing
        #expect(report.canSend)
    }

    @Test("send: the payload carries exactly the page under report")
    func payloadAssembly() async throws {
        let page = entry()
        let submitter = RecordingSubmitter()
        let report = model(entry: page, submitter: submitter)
        report.reason = .wrongOrNonsense
        report.note = "  it contradicted itself  "

        await report.send()

        #expect(report.phase == .sent)
        let sent = try #require(submitter.attempts.first)
        #expect(sent.replyID == page.id)
        #expect(sent.pageID == page.id, "one archive entry is the page+reply pair")
        #expect(sent.bookID == BookID.oracle.rawValue)
        #expect(sent.reason == "wrong_or_nonsense")
        #expect(sent.note == "it contradicted itself", "the note travels trimmed")
        #expect(sent.replyKind == "ink")
        #expect(sent.replyText == page.replyText)
        #expect(sent.assetRef == nil)
        #expect(sent.modelID.isEmpty, "the archive records no serving model — no guessing")
        #expect(sent.snapshotDigest == String(repeating: "ab", count: 32))
        #expect(sent.snapshotBase64 == Data("report-snapshot".utf8).base64EncodedString())
        #expect(sent.createdAt == page.createdAt)
        #expect(sent.submittedAt > page.createdAt)
    }

    @Test("an empty note travels as nothing, not as an empty string")
    func emptyNoteIsNil() async throws {
        let submitter = RecordingSubmitter()
        let report = model(entry: entry(), submitter: submitter)
        report.reason = .somethingElse
        report.note = "   "

        await report.send()
        let sent = try #require(submitter.attempts.first)
        #expect(sent.note == nil)
    }

    @Test("the note is capped at 500 characters")
    func noteCap() {
        let report = model(entry: entry())
        report.note = String(repeating: "n", count: 600)
        #expect(report.note.count == ReportModel.noteLimit)
    }

    @Test("failure: the sheet stays open and a retry reuses the same reportID")
    func failureKeepsTheSheetOpen() async throws {
        let submitter = RecordingSubmitter()
        submitter.failure = .offline
        let report = model(entry: entry(), submitter: submitter)
        report.reason = .disturbing
        report.note = "the words unsettled me"

        await report.send()

        guard case .failed = report.phase else {
            Issue.record("an offline send must land in .failed; got \(report.phase)")
            return
        }
        #expect(report.reason == .disturbing, "the choice survives the failure")
        #expect(report.note == "the words unsettled me", "the note survives the failure")
        #expect(report.canSend, "the sheet stays open for a retry")

        submitter.failure = nil
        await report.send()

        #expect(report.phase == .sent)
        #expect(submitter.attempts.count == 2)
        #expect(
            submitter.attempts[0].reportID == submitter.attempts[1].reportID,
            "the retry reuses the reportID so the server files one report"
        )
    }

    @Test("the Keeper's consent line names the seal; open Books get the plain line")
    func keeperConsent() {
        let keeperReport = model(entry: entry(book: .keeper), book: .by(id: .keeper))
        let openReport = model(entry: entry(), book: .by(id: .oracle))

        #expect(keeperReport.isPrivatePage)
        #expect(!openReport.isPrivatePage)
        #expect(keeperReport.consentLine != openReport.consentLine)
        #expect(
            keeperReport.consentLine.contains("Keeper")
                && keeperReport.consentLine.contains("seal"),
            "reporting a sealed page must say so, in those words"
        )
        for line in [keeperReport.consentLine, openReport.consentLine] {
            #expect(
                line.contains("Nothing leaves this device until you press send"),
                "the consent line carries the only-on-submit promise verbatim"
            )
        }
    }

    @Test("a successful send tracks report_submitted with the reason enum only")
    func analyticsCarriesReasonOnly() async throws {
        let sink = RecordingSink()
        let submitter = RecordingSubmitter()
        let report = model(entry: entry(), submitter: submitter, sink: sink)
        report.reason = .notWhatIAsked
        report.note = "private words that must not reach analytics"

        await report.send()

        let event = try #require(sink.events.first)
        #expect(event.name == "report_submitted")
        #expect(event.parameters["reason"] == .string("not_what_i_asked"))
        #expect(event.parameters["book"] == .string(BookID.oracle.rawValue))
        #expect(event.parameters.count == 2, "the note and page content never enter analytics")
    }

    @Test("sent is terminal: the seal cannot be pressed twice")
    func sentIsTerminal() async {
        let submitter = RecordingSubmitter()
        let report = model(entry: entry(), submitter: submitter)
        report.reason = .disturbing

        await report.send()
        #expect(report.phase == .sent)
        #expect(!report.canSend)

        await report.send()
        #expect(submitter.attempts.count == 1, "a second press files nothing new")
    }
}
