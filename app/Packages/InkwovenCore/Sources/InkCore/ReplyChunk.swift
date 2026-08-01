import Foundation

/// A unit of the server's SSE stream for one exchange. The server decides
/// modality; the client only dispatches. Unknown wire kinds are dropped at
/// decode time (forward compatibility with post-launch Book drops).
public enum ReplyChunk: Equatable, Sendable {
    case inkDelta(String)
    case imageIntent(ImageJob)
    case videoIntent(VideoJob)
    case imagePreview(Data)
    case imageFinal(URL)
    /// The develop failed server-side. Terminal for the slot `imageIntent`
    /// opened: without it the darkroom spins until the exchange ends.
    case imageFailed(ImageFailure)
    case videoFinal(URL)
    case crisis(CrisisPayload)
    case done(Usage)
}

public struct ImageJob: Equatable, Sendable, Codable {
    public var id: String
    public var expectsPreview: Bool

    public init(id: String, expectsPreview: Bool = true) {
        self.id = id
        self.expectsPreview = expectsPreview
    }
}

public struct VideoJob: Equatable, Sendable, Codable {
    public var id: String

    public init(id: String) { self.id = id }
}

/// Why a develop never arrived. `reason` is a server-side diagnostic string —
/// it is never shown to the reader, who sees the Book's own in-fiction line.
public struct ImageFailure: Equatable, Sendable, Codable {
    public var id: String
    public var reason: String?

    public init(id: String, reason: String? = nil) {
        self.id = id
        self.reason = reason
    }
}

/// Crisis payloads preempt the stream: the shell cancels renderers, discards
/// partial fiction, and surfaces this plainly (unbranded CrisisCard).
public struct CrisisPayload: Equatable, Sendable, Codable {
    public struct Resource: Equatable, Sendable, Codable {
        public var name: String
        public var contact: String

        public init(name: String, contact: String) {
            self.name = name
            self.contact = contact
        }
    }

    public var message: String
    public var resources: [Resource]

    public init(message: String, resources: [Resource]) {
        self.message = message
        self.resources = resources
    }
}

public struct Usage: Equatable, Sendable, Codable {
    public var modelID: String
    public var inputTokens: Int
    public var outputTokens: Int

    public init(modelID: String, inputTokens: Int, outputTokens: Int) {
        self.modelID = modelID
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
    }
}

/// Context sent alongside a snapshot. Memory summaries are Plus-only and
/// already filtered (torn-out entries never leave the device).
public struct PageContext: Equatable, Sendable, Codable {
    public var priorInkText: String?
    public var memorySummaries: [String]
    public var sessionSummary: String?

    public init(priorInkText: String? = nil, memorySummaries: [String] = [], sessionSummary: String? = nil) {
        self.priorInkText = priorInkText
        self.memorySummaries = memorySummaries
        self.sessionSummary = sessionSummary
    }
}
