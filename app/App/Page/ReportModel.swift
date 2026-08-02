import Foundation
import PencilKit
import InkCore
import InkNet
import InkAnalytics

/// Why a reply is being reported. Raw values are the wire constants the proxy
/// validates against; `label` is what the sheet shows.
enum ReportReason: String, CaseIterable, Equatable {
    case disturbing = "disturbing"
    case wrongOrNonsense = "wrong_or_nonsense"
    case notWhatIAsked = "not_what_i_asked"
    case somethingElse = "something_else"

    var label: String {
        switch self {
        case .disturbing: "disturbing"
        case .wrongOrNonsense: "wrong or nonsense"
        case .notWhatIAsked: "not what I asked"
        case .somethingElse: "something else"
        }
    }

    var spoken: String {
        switch self {
        case .disturbing: "Disturbing"
        case .wrongOrNonsense: "Wrong or nonsense"
        case .notWhatIAsked: "Not what I asked"
        case .somethingElse: "Something else"
        }
    }
}

/// The report sheet's seam over ProxyClient — the sheet never holds the
/// concrete client, and the tests script this instead.
protocol ReportSubmitting: Sendable {
    func report(_ payload: ReportPayload) async throws
}

extension ProxyClient: ReportSubmitting {}

/// Renders the reported page for the payload — at submit time, never before.
/// The archive keeps strokes, not images, so the picture is drawn fresh the
/// moment the user sends and discarded with the payload.
@MainActor
protocol ReportSnapshotting {
    func snapshot(strokeData: Data, typedText: String?) throws -> SnapshotPayload
}

enum ReportSnapshotError: Error {
    case nothingToPicture
}

/// Live rasterizer over the same pipeline the exchange path uses: strokes
/// through PKDrawingRasterizer, the typed hand through TypedInkRasterizer.
struct LiveReportSnapshotter: ReportSnapshotting {
    func snapshot(strokeData: Data, typedText: String?) throws -> SnapshotPayload {
        let drawing = (try? PKDrawing(data: strokeData)) ?? PKDrawing()
        if !drawing.strokes.isEmpty {
            let crop = drawing.bounds.insetBy(dx: -24, dy: -24)
            let target = SnapshotPlanner.targetPixelSize(for: crop.size)
            let data = try PKDrawingRasterizer(drawing: drawing)
                .rasterize(cropRect: crop, targetPixelSize: target)
            return SnapshotPayload(
                imageData: data,
                digest: SnapshotProcessor.digest(of: data),
                cropRect: crop,
                pixelSize: target
            )
        }
        if let typed = typedText, !typed.isEmpty,
           let payload = TypedInkRasterizer.payload(text: typed, pageWidth: 700) {
            return payload
        }
        throw ReportSnapshotError.nothingToPicture
    }
}

/// State behind ReportSheet: reason gating, the 500-character note cap, the
/// consent line (the Keeper gets a stronger one), and a submit that fails
/// in-fiction and keeps the sheet open. One `reportID` per sheet, minted at
/// init — a retry reuses it, so the server files a single report however
/// many times the send is tapped.
@Observable
@MainActor
final class ReportModel {
    enum Phase: Equatable {
        case composing
        case sending
        case sent
        case failed(String)
    }

    static let noteLimit = 500

    let entry: PageArchive.Entry
    let book: Book

    var reason: ReportReason?
    var note: String = "" {
        didSet {
            if note.count > Self.noteLimit {
                note = String(note.prefix(Self.noteLimit))
            }
        }
    }
    private(set) var phase: Phase = .composing

    private let submitter: any ReportSubmitting
    private let analytics: Analytics
    private let snapshotter: any ReportSnapshotting
    private let reportID = UUID()

    init(
        entry: PageArchive.Entry,
        book: Book,
        submitter: any ReportSubmitting,
        analytics: Analytics,
        snapshotter: any ReportSnapshotting = LiveReportSnapshotter()
    ) {
        self.entry = entry
        self.book = book
        self.submitter = submitter
        self.analytics = analytics
        self.snapshotter = snapshotter
    }

    var canSend: Bool {
        reason != nil && phase != .sending && phase != .sent
    }

    /// The Keeper's lock is a promise; carrying a sealed page out must never
    /// read like carrying any other. Same flow, stronger words.
    var isPrivatePage: Bool { book.locked }

    /// Plain language, above the send seal, naming exactly what travels.
    var consentLine: String {
        if isPrivatePage {
            return "This page is the Keeper's, sealed behind your face on this device. Sending this report carries this private page out from behind the seal — the reply, your strokes from that page, which Book it came from, and when it was written. Nothing leaves this device until you press send."
        }
        return "Sending this shows the binder: the reply, your strokes from that page, which Book it came from, and when it was written. Nothing leaves this device until you press send."
    }

    func send() async {
        guard let reason, canSend else { return }
        phase = .sending
        do {
            let snapshot = try snapshotter.snapshot(
                strokeData: entry.strokeData, typedText: entry.typedText
            )
            try await submitter.report(payload(reason: reason, snapshot: snapshot))
            phase = .sent
            await analytics.track(
                .reportSubmitted(book: BookID(rawValue: entry.bookID), reason: reason.rawValue)
            )
        } catch {
            phase = .failed(Self.failureLine(for: error))
        }
    }

    private func payload(reason: ReportReason, snapshot: SnapshotPayload) -> ReportPayload {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return ReportPayload(
            reportID: reportID,
            // The live archive keeps a page and its reply as one entry (one
            // UUID); both IDs carry it until InkData's split schema binds.
            replyID: entry.id,
            pageID: entry.id,
            bookID: entry.bookID,
            reason: reason.rawValue,
            note: trimmed.isEmpty ? nil : trimmed,
            replyKind: "ink",
            replyText: entry.replyText,
            assetRef: nil,
            // The archive does not record which model served a reply; an
            // empty modelID is the honest value, not a guess.
            modelID: "",
            snapshotDigest: snapshot.digest,
            snapshotBase64: snapshot.imageData.base64EncodedString(),
            createdAt: entry.createdAt,
            submittedAt: .now
        )
    }

    /// Failures stay in-fiction and keep the sheet open; the report is the
    /// user's to retry or abandon, never queued behind their back.
    static func failureLine(for error: Error) -> String {
        if case ProxyError.offline = error {
            return "The road is dark — the report cannot travel tonight. It stays here with you; try again when the way opens."
        }
        return "The binder could not take this page just now. Nothing was lost — try again in a moment."
    }
}
