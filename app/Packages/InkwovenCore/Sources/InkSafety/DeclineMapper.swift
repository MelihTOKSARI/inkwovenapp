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

/// Which exchange surface the failure happened on. Kept because the copy and
/// the refund promise differ per surface; moderation no longer does.
public enum DeclineSurface: Sendable {
    case ink
    case image
    case video
}

public enum DeclineMapper {
    public static func map(_ error: ProxyError, surface: DeclineSurface) -> InFictionState {
        switch error {
        // A provider block used to route the INK surface to the crisis card
        // (audit S-1), on the theory that the most explicit disclosures are
        // the ones blocked before the Book can answer. In practice the signal
        // does not carry that meaning: providers block dark fiction, villains,
        // peril and the occasional stray page, and none of them arrive with a
        // self-harm category attached — every provider path collapses to a
        // bare `moderated`. So the escalation fired mostly on writers who were
        // simply writing, and a false crisis card is its own harm: the fiction
        // breaks, the page is interrupted, and a reader is handed a helpline
        // for a villain's monologue.
        //
        // Crisis detection stays where it can actually be reasoned about: the
        // reply model's `[[CRISIS]]` sentinel and the proxy's own deterministic
        // screen, both of which see the words. The client invents nothing.
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
