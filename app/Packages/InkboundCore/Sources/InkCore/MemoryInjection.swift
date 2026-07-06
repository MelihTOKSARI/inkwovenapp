import Foundation

/// Value form of a per-Book memory summary (the SwiftData model lives in
/// InkData; this keeps the injection rule pure and testable).
public struct MemorySummary: Equatable, Sendable {
    public var bookID: BookID
    public var summary: String
    public var updatedAt: Date
    public var tornOut: Bool

    public init(bookID: BookID, summary: String, updatedAt: Date, tornOut: Bool = false) {
        self.bookID = bookID
        self.summary = summary
        self.updatedAt = updatedAt
        self.tornOut = tornOut
    }
}

/// Cross-page memory injection (task D5). Plus-only; torn-out memories never
/// reappear in context — the tear is honored here, before anything leaves the
/// device.
public enum MemoryInjection {
    public static func summaries(
        for book: BookID,
        from entries: [MemorySummary],
        memoryEnabled: Bool,
        limit: Int = 5
    ) -> [String] {
        guard memoryEnabled else { return [] }
        return entries
            .filter { $0.bookID == book && !$0.tornOut }
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(limit)
            .map(\.summary)
    }
}
