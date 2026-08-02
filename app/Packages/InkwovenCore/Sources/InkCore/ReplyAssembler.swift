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
    /// Close the slot `openDevelopSlot` opened — the picture will never arrive.
    /// The ink still stands: a failed develop never fails the exchange.
    case closeDevelopSlot(ImageFailure)
    /// Shell must obtain a `CreditReservation` from InkMoney before
    /// acknowledging the job; on failure the job is declined in-fiction.
    case requestVideoCredit(VideoJob)
    /// The counterpart to `requestVideoCredit`: the job will never deliver, so
    /// the shell must release the hold it took. Without this the reservation
    /// is stranded forever — `CreditLedger.available` is `balance - held`, so a
    /// leaked hold silently makes a credit permanently unspendable.
    case releaseVideoCredit(VideoJob)
    case playVideo(URL)
    /// The page may OFFER to move (task J3). Advisory: the affordance appears,
    /// and nothing is generated or charged until the reader taps it.
    case offerVideo(ConvertibilityVerdict)
    /// Preemption: cancel all renderers, discard partial fiction, surface the
    /// payload plainly. No further fiction outputs will be emitted.
    case crisis(CrisisPayload)
    case completed(AssembledReply)
}

public struct AssembledReply: Equatable, Sendable {
    public var inkText: String
    public var imageURL: URL?
    public var videoURL: URL?
    /// Present when the Book judged this reply worth moving. Carried on the
    /// finished reply so a revisited page can still offer.
    public var verdict: ConvertibilityVerdict?
    public var usage: Usage

    public init(
        inkText: String,
        imageURL: URL? = nil,
        videoURL: URL? = nil,
        verdict: ConvertibilityVerdict? = nil,
        usage: Usage
    ) {
        self.inkText = inkText
        self.imageURL = imageURL
        self.videoURL = videoURL
        self.verdict = verdict
        self.usage = usage
    }
}

/// Consumes the chunk stream for one exchange. Value type; the shell owns one
/// per in-flight exchange.
public struct ReplyAssembler: Sendable {
    public private(set) var inkText: String = ""
    public private(set) var imageURL: URL?
    public private(set) var videoURL: URL?
    /// The convertibility verdict, when the Book returned a positive one.
    public private(set) var verdict: ConvertibilityVerdict?
    public private(set) var isPreempted = false
    /// Video jobs whose credit the shell was told to reserve and which have
    /// not delivered yet. Any exchange ending with entries still here owes the
    /// user a release.
    public private(set) var pendingVideoJobs: [VideoJob] = []

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

        case .imageFailed(let failure):
            return [.closeDevelopSlot(failure)]

        case .videoIntent(let job):
            pendingVideoJobs.append(job)
            return [.requestVideoCredit(job)]

        case .videoFinal(let url):
            videoURL = url
            // The wire carries one video job per exchange, so the final
            // resolves the outstanding intent.
            pendingVideoJobs.removeAll()
            return [.playVideo(url)]

        case .videoFailed(let failure):
            // Terminal for the intent: the clip will never arrive, so the hold
            // must go back now rather than waiting for the stream to end.
            pendingVideoJobs.removeAll { $0.id == failure.id }
            return [.releaseVideoCredit(VideoJob(id: failure.id))]

        case .verdict(let verdict):
            // Advisory (task J2): a negative verdict is simply never sent, so
            // an explicit `false` is honoured the same way — the page offers
            // only on a positive one. Nothing here starts a generation.
            guard verdict.convertible else { return [] }
            self.verdict = verdict
            return [.offerVideo(verdict)]

        case .crisis(let payload):
            isPreempted = true
            // Releases lead: a shell that treats `.crisis` as "stop everything
            // and tear down" would otherwise never reach the release and would
            // strand the hold on the one exchange we least want to bill.
            return drainPendingVideoCredits() + [.crisis(payload)]

        case .done(let usage):
            let reply = AssembledReply(
                inkText: inkText,
                imageURL: imageURL,
                videoURL: videoURL,
                verdict: verdict,
                usage: usage
            )
            // A stream that ends without the clip it promised still owes the
            // release.
            return drainPendingVideoCredits() + [.completed(reply)]
        }
    }

    /// The stream ended abnormally (transport error, cancellation) — the shell
    /// calls this from its catch block so a held credit is not lost with it.
    public mutating func abandon() -> [AssemblerOutput] {
        drainPendingVideoCredits()
    }

    private mutating func drainPendingVideoCredits() -> [AssemblerOutput] {
        defer { pendingVideoJobs.removeAll() }
        return pendingVideoJobs.map { .releaseVideoCredit($0) }
    }
}
