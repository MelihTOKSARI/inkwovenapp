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
    /// Provider moderation of the writer's own page (audit S-1). The more
    /// explicit a disclosure, the more likely the provider blocks it before
    /// the Book can answer — so a block on the ink path routes to the crisis
    /// card, never to an in-fiction shrug with a retry button. This is the
    /// one state here that deliberately BREAKS fiction.
    case crisisSuspect
}

/// Which exchange surface the failure happened on. Moderation means different
/// things on each: a blocked INK page is the writer's own words being refused
/// — crisis-suspect by construction — while a blocked image or clip is
/// genuinely just a picture that will not be made.
public enum DeclineSurface: Sendable {
    case ink
    case image
    case video
}

public enum DeclineMapper {
    public static func map(_ error: ProxyError, surface: DeclineSurface) -> InFictionState {
        switch error {
        case .moderated:
            surface == .ink ? .crisisSuspect : .pageDeclines
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
