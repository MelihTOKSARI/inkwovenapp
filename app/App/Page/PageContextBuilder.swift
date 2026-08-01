import Foundation
import InkCore

/// Where the page's cross-Book memory comes from. Nothing writes summaries yet
/// (task D5), so the live binding is empty and the notebook honestly
/// remembers nothing.
///
/// The seam is here, on the client, because `MemoryInjection` has to run before
/// the request is built: a torn-out memory must never leave the device, and a
/// server-side filter would already be too late.
@MainActor
protocol MemoryProviding {
    func summaries(for book: BookID) -> [MemorySummary]
}

/// The honest default until summarization binds.
struct EmptyMemoryProvider: MemoryProviding {
    init() {}
    func summaries(for book: BookID) -> [MemorySummary] { [] }
}

/// Builds the `PageContext` that rides with a snapshot.
///
/// Every field used to arrive empty at both call sites, so the Book had no
/// memory of the exchange the user could still see on screen, and
/// `MemoryInjection` had no production call site at all. The proxy treats this
/// text as untrusted input and fences it server-side; the tear is honored here.
enum PageContextBuilder {
    /// The exchange this page last completed, as the page shows it.
    struct Turn: Equatable {
        var written: String?
        var reply: String
    }

    /// A session summary is one line, not a transcript — the snapshot already
    /// carries the ink, and an unbounded summary is an unbounded token bill.
    private static let sessionSummaryLimit = 240

    static func context(
        book: BookID,
        lastTurn: Turn?,
        memories: [MemorySummary],
        memoryEnabled: Bool
    ) -> PageContext {
        PageContext(
            priorInkText: lastTurn?.written,
            memorySummaries: MemoryInjection.summaries(
                for: book, from: memories, memoryEnabled: memoryEnabled
            ),
            sessionSummary: sessionSummary(lastTurn)
        )
    }

    private static func sessionSummary(_ turn: Turn?) -> String? {
        guard let turn else { return nil }
        let reply = turn.reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reply.isEmpty else { return nil }
        return "Earlier on this page you answered: " + String(reply.prefix(sessionSummaryLimit))
    }
}
