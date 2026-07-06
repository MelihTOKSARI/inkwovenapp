import Foundation
import InkCore

public enum AnalyticsValue: Equatable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
}

/// The funnel + NSM schema (task A3). Names are snake_case wire constants;
/// adding an event means adding a case — no stringly-typed tracking anywhere
/// else in the codebase.
public enum AnalyticsEvent: Equatable, Sendable {
    case install
    case firstStroke
    case pageSent(book: BookID)
    /// The NSM atom: a magic moment. `ttfsMS` feeds the p50/p95
    /// time-to-first-stroke instrument (latency budget is launch-blocking).
    case pageAnswered(book: BookID, modality: Modality, ttfsMS: Int)
    case secondBookOpened(book: BookID)
    case paywallShown(trigger: String)
    case purchase(sku: String)
    case creditSpent(amount: Int)
    case creditRefunded(amount: Int)
    case crisisFlow(book: BookID)
    case cooldownHit(seconds: Double)
    case memoryTorn(book: BookID)

    public var name: String {
        switch self {
        case .install: "install"
        case .firstStroke: "first_stroke"
        case .pageSent: "page_sent"
        case .pageAnswered: "page_answered"
        case .secondBookOpened: "second_book_opened"
        case .paywallShown: "paywall_shown"
        case .purchase: "purchase"
        case .creditSpent: "credit_spent"
        case .creditRefunded: "credit_refunded"
        case .crisisFlow: "crisis_flow"
        case .cooldownHit: "cooldown_hit"
        case .memoryTorn: "memory_torn"
        }
    }

    public var parameters: [String: AnalyticsValue] {
        switch self {
        case .install, .firstStroke:
            [:]
        case .pageSent(let book):
            ["book": .string(book.rawValue)]
        case .pageAnswered(let book, let modality, let ttfsMS):
            ["book": .string(book.rawValue), "modality": .string(modality.rawValue), "ttfs_ms": .int(ttfsMS)]
        case .secondBookOpened(let book):
            ["book": .string(book.rawValue)]
        case .paywallShown(let trigger):
            ["trigger": .string(trigger)]
        case .purchase(let sku):
            ["sku": .string(sku)]
        case .creditSpent(let amount):
            ["amount": .int(amount)]
        case .creditRefunded(let amount):
            ["amount": .int(amount)]
        case .crisisFlow(let book):
            ["book": .string(book.rawValue)]
        case .cooldownHit(let seconds):
            ["seconds": .double(seconds)]
        case .memoryTorn(let book):
            ["book": .string(book.rawValue)]
        }
    }
}

/// Single adapter boundary — the concrete SDK is bound once in App/DI.
public protocol AnalyticsSink: Sendable {
    func track(name: String, parameters: [String: AnalyticsValue])
}

public actor Analytics {
    private let sink: any AnalyticsSink

    public init(sink: any AnalyticsSink) {
        self.sink = sink
    }

    public func track(_ event: AnalyticsEvent) {
        sink.track(name: event.name, parameters: event.parameters)
    }
}
