import Foundation

/// Stamps `t_send` and measures time-to-first-stroke — the launch-blocking
/// latency metric (first ink stroke ≤4s p95). Reported with every exchange.
public struct ExchangeTimer: Sendable {
    public let sentAt: Date
    public private(set) var firstChunkAt: Date?

    public init(sentAt: Date = Date()) {
        self.sentAt = sentAt
    }

    /// Records the first chunk arrival; later calls are ignored.
    /// Returns ttfs in ms the first time, nil after.
    @discardableResult
    public mutating func markFirstChunk(at date: Date = Date()) -> Int? {
        guard firstChunkAt == nil else { return nil }
        firstChunkAt = date
        return ttfsMS
    }

    public var ttfsMS: Int? {
        guard let firstChunkAt else { return nil }
        return Int((firstChunkAt.timeIntervalSince(sentAt) * 1000).rounded())
    }
}
