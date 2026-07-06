import Foundation

/// Typed transport/application errors. The shell maps these to in-fiction
/// states (see InkSafety.DeclineMapper); raw errors never reach the page.
public enum ProxyError: Error, Equatable, Sendable {
    case offline
    case transport(String)
    case server(status: Int)
    /// Moderation rejection — soft-declined in fiction, never auto-retried,
    /// category detail never exposed.
    case moderated
    case rateLimited(retryAfterSeconds: Double?)
    case badResponse
    case cancelled
}

/// Exponential retry on transport failures only — never on moderation
/// rejections, never on server-side application errors.
public enum RetryPolicy {
    public static let maxAttempts = 2

    public static func shouldRetry(_ error: ProxyError, attempt: Int) -> Bool {
        guard attempt < maxAttempts else { return false }
        switch error {
        case .offline, .transport:
            return true
        case .server, .moderated, .rateLimited, .badResponse, .cancelled:
            return false
        }
    }

    /// 0-based attempt → backoff before the next try.
    public static func delay(beforeAttempt attempt: Int) -> TimeInterval {
        0.5 * pow(2.0, Double(attempt))
    }
}
