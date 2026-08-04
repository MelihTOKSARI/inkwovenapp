import Foundation
import InkCore

/// Crisis handling (task F1). The proxy decides — a deterministic in-process
/// screen over the writer's context and the assembled reply, plus the reply
/// model's own `[[CRISIS]]` sentinel as the fast path (proxy/src/models.js,
/// server.js). This type is the CLIENT half and contains no text matching of
/// its own: a `.crisis` chunk preempts the exchange — cancel renderers,
/// discard partial fiction, surface the payload plainly. The exchange is not
/// billed as a moment.
public enum CrisisVerdict: Equatable, Sendable {
    case passthrough(ReplyChunk)
    /// Terminal: nothing further passes for this exchange.
    case preempt(CrisisPayload)
    case discard
}

public struct CrisisGuard: Sendable {
    public private(set) var isPreempted = false

    public init() {}

    public mutating func inspect(_ chunk: ReplyChunk) -> CrisisVerdict {
        guard !isPreempted else { return .discard }
        if case .crisis(let payload) = chunk {
            isPreempted = true
            return .preempt(payload)
        }
        return .passthrough(chunk)
    }
}

public enum CrisisInterceptor {
    /// Wraps an exchange stream: fiction chunks pass through until a crisis
    /// chunk appears, at which point the crisis is emitted and the stream
    /// terminates immediately — the renderer is cancelled within one chunk.
    public static func intercept(
        _ upstream: AsyncThrowingStream<ReplyChunk, Error>
    ) -> AsyncThrowingStream<ReplyChunk, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var guardState = CrisisGuard()
                do {
                    for try await chunk in upstream {
                        switch guardState.inspect(chunk) {
                        case .passthrough(let chunk):
                            continuation.yield(chunk)
                        case .preempt(let payload):
                            continuation.yield(.crisis(payload))
                            continuation.finish()
                            return
                        case .discard:
                            continue
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// Billing rule: a preempted exchange never counts against the user's daily
/// moments.
public enum MomentBilling {
    public static func isBillable(_ chunks: [ReplyChunk]) -> Bool {
        !chunks.contains { if case .crisis = $0 { true } else { false } }
    }
}
