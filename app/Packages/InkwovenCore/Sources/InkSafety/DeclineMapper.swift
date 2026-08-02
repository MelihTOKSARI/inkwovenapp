import Foundation
import InkNet

/// In-fiction states the page can show. Raw errors, moderation categories, and
/// HTTP codes never reach the paper (task F2 / C6).
public enum InFictionState: Equatable, Sendable {
    /// Moderation soft decline — the page demurs. Never auto-retried.
    case pageDeclines
    /// Rate limit / cooldown — "the ink must rest."
    case inkMustRest(seconds: Double?)
    /// Offline — the page is quiet until the connection returns.
    case pageIsQuiet
    /// Transient fault after retries — invite the user to try again.
    case inkRanDry
    /// The vials are empty and no free clip stands: the shop, not an error.
    case vialsEmpty
}

public enum DeclineMapper {
    public static func map(_ error: ProxyError) -> InFictionState {
        switch error {
        case .moderated:
            .pageDeclines
        case .rateLimited(let retryAfter):
            .inkMustRest(seconds: retryAfter)
        case .offline:
            .pageIsQuiet
        case .paymentRequired:
            .vialsEmpty
        case .transport, .server, .badResponse, .cancelled:
            .inkRanDry
        }
    }

    /// Only transport-class failures may be retried automatically, and
    /// moderation never is — enforced here in addition to RetryPolicy.
    public static func mayAutoRetry(_ error: ProxyError) -> Bool {
        RetryPolicy.shouldRetry(error, attempt: 0)
    }
}
