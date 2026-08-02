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
    case notificationPermissionAnswered(granted: Bool)
    /// An app open attributed to the evening ritual's notification; `book` is
    /// the voice that asked.
    case ritualOpened(book: BookID)
    /// User-triggered report of a reply (guideline 1.2). Carries the reason
    /// enum only — never the note, never page content.
    case reportSubmitted(book: BookID, reason: String)

    // -- moving pictures (task J9) -------------------------------------------
    // Two ratios matter. offered→requested is how the convertibility verdict
    // (J2) gets tuned: offers nobody takes mean the model is misreading what
    // it wrote. requested→delivered is the REAL failure rate, which replaces
    // the assumed 8% in design/app-store-assets/credits.md §2.

    /// The page offered to move — a positive verdict reached the reader.
    case videoOffered(book: BookID)
    /// The reader tapped. `free` records which purse it came from.
    case videoRequested(book: BookID, free: Bool)
    /// The clip bloomed on the page. `waitedMS` is the theatre's real duration.
    case videoDelivered(book: BookID, waitedMS: Int)
    /// No clip, and the credit went back. `reason` is a coarse bucket, never
    /// a provider string or anything from the page.
    case videoFailed(book: BookID, reason: String)
    /// The clip was tapped and filled the screen — the Riddle-diary moment.
    case videoImmersiveOpened(book: BookID)

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
        case .notificationPermissionAnswered: "notification_permission_answered"
        case .ritualOpened: "ritual_opened"
        case .reportSubmitted: "report_submitted"
        case .videoOffered: "video_offered"
        case .videoRequested: "video_requested"
        case .videoDelivered: "video_delivered"
        case .videoFailed: "video_failed"
        case .videoImmersiveOpened: "video_immersive_opened"
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
        case .notificationPermissionAnswered(let granted):
            ["granted": .bool(granted)]
        case .ritualOpened(let book):
            ["book": .string(book.rawValue)]
        case .reportSubmitted(let book, let reason):
            ["book": .string(book.rawValue), "reason": .string(reason)]
        case .videoOffered(let book):
            ["book": .string(book.rawValue)]
        case .videoRequested(let book, let free):
            ["book": .string(book.rawValue), "free": .bool(free)]
        case .videoDelivered(let book, let waitedMS):
            ["book": .string(book.rawValue), "waited_ms": .int(waitedMS)]
        case .videoFailed(let book, let reason):
            ["book": .string(book.rawValue), "reason": .string(reason)]
        case .videoImmersiveOpened(let book):
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
