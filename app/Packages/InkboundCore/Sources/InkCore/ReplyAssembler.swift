import Foundation

/// What the shell must do in response to consumed chunks. The assembler is the
/// client half of the modality router (task C2): the server decides modality,
/// this dispatches to renderers and materializes the `Reply`.
public enum AssemblerOutput: Equatable, Sendable {
    /// Feed the ink renderer immediately — streaming-first, never wait for a
    /// completed reply.
    case appendInk(String)
    /// Open a develop slot on the page (preview-first darkroom fiction).
    case openDevelopSlot(ImageJob)
    case renderImagePreview(Data)
    case renderImageFinal(URL)
    /// Shell must obtain a `CreditReservation` from InkMoney before
    /// acknowledging the job; on failure the job is declined in-fiction.
    case requestVideoCredit(VideoJob)
    case playVideo(URL)
    /// Preemption: cancel all renderers, discard partial fiction, surface the
    /// payload plainly. No further fiction outputs will be emitted.
    case crisis(CrisisPayload)
    case completed(AssembledReply)
}

public struct AssembledReply: Equatable, Sendable {
    public var inkText: String
    public var imageURL: URL?
    public var videoURL: URL?
    public var usage: Usage

    public init(inkText: String, imageURL: URL? = nil, videoURL: URL? = nil, usage: Usage) {
        self.inkText = inkText
        self.imageURL = imageURL
        self.videoURL = videoURL
        self.usage = usage
    }
}

/// Consumes the chunk stream for one exchange. Value type; the shell owns one
/// per in-flight exchange.
public struct ReplyAssembler: Sendable {
    public private(set) var inkText: String = ""
    public private(set) var imageURL: URL?
    public private(set) var videoURL: URL?
    public private(set) var isPreempted = false

    public init() {}

    @discardableResult
    public mutating func consume(_ chunk: ReplyChunk) -> [AssemblerOutput] {
        // After a crisis preemption the fiction is over for this exchange —
        // everything else in the stream is discarded.
        guard !isPreempted else { return [] }

        switch chunk {
        case .inkDelta(let delta):
            inkText += delta
            return [.appendInk(delta)]

        case .imageIntent(let job):
            return [.openDevelopSlot(job)]

        case .imagePreview(let data):
            return [.renderImagePreview(data)]

        case .imageFinal(let url):
            imageURL = url
            return [.renderImageFinal(url)]

        case .videoIntent(let job):
            return [.requestVideoCredit(job)]

        case .videoFinal(let url):
            videoURL = url
            return [.playVideo(url)]

        case .crisis(let payload):
            isPreempted = true
            return [.crisis(payload)]

        case .done(let usage):
            let reply = AssembledReply(inkText: inkText, imageURL: imageURL, videoURL: videoURL, usage: usage)
            return [.completed(reply)]
        }
    }
}
