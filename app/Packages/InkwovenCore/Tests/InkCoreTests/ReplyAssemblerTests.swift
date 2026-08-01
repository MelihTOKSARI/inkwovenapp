import Foundation
import Testing
@testable import InkCore

@Suite("ReplyAssembler / modality dispatch (task C2)")
struct ReplyAssemblerTests {
    let usage = Usage(modelID: "flash-lite", inputTokens: 120, outputTokens: 80)

    @Test("ink deltas stream straight through and accumulate")
    func inkAccumulates() {
        var a = ReplyAssembler()
        #expect(a.consume(.inkDelta("The page ")) == [.appendInk("The page ")])
        #expect(a.consume(.inkDelta("stirs.")) == [.appendInk("stirs.")])
        #expect(a.inkText == "The page stirs.")
    }

    @Test("image intent opens a develop slot; preview renders before final swaps in")
    func imagePreviewFirst() throws {
        var a = ReplyAssembler()
        let job = ImageJob(id: "img-1")
        let url = try #require(URL(string: "https://assets.inkwoven.app/img-1.jpg"))

        #expect(a.consume(.imageIntent(job)) == [.openDevelopSlot(job)])
        #expect(a.consume(.imagePreview(Data([0xFF]))) == [.renderImagePreview(Data([0xFF]))])
        #expect(a.consume(.imageFinal(url)) == [.renderImageFinal(url)])
        #expect(a.imageURL == url)
    }

    @Test("video intent demands a credit reservation before anything plays")
    func videoRequiresCredit() {
        var a = ReplyAssembler()
        let job = VideoJob(id: "vid-1")
        #expect(a.consume(.videoIntent(job)) == [.requestVideoCredit(job)])
    }

    @Test("crisis preempts: every subsequent fiction chunk is discarded")
    func crisisPreempts() {
        var a = ReplyAssembler()
        let payload = CrisisPayload(message: "You matter.", resources: [.init(name: "988 Lifeline", contact: "988")])

        _ = a.consume(.inkDelta("Once upon"))
        #expect(a.consume(.crisis(payload)) == [.crisis(payload)])
        #expect(a.isPreempted)
        #expect(a.consume(.inkDelta(" a time")).isEmpty)
        #expect(a.consume(.imageIntent(ImageJob(id: "x"))).isEmpty)
        #expect(a.consume(.done(usage)).isEmpty, "a preempted exchange never completes as fiction")
        #expect(a.inkText == "Once upon", "partial fiction is frozen, not extended")
    }

    @Test("crisis releases a held video credit and is never billed")
    func crisisReleasesVideoHold() {
        var a = ReplyAssembler()
        let job = VideoJob(id: "vid-1")
        let payload = CrisisPayload(message: "You matter.", resources: [])

        #expect(a.consume(.videoIntent(job)) == [.requestVideoCredit(job)])
        #expect(a.pendingVideoJobs == [job])

        // The release leads so a shell that tears down on `.crisis` still sees
        // it. Without this the hold is stranded and `available` is permanently
        // short by one vial.
        #expect(a.consume(.crisis(payload)) == [.releaseVideoCredit(job), .crisis(payload)])
        #expect(a.pendingVideoJobs.isEmpty)
        #expect(a.isPreempted)
        #expect(a.consume(.videoFinal(URL(string: "https://x/clip.mp4")!)).isEmpty)
    }

    @Test("a stream that ends without the promised clip still releases the hold")
    func doneWithoutVideoReleases() {
        var a = ReplyAssembler()
        let job = VideoJob(id: "vid-1")
        _ = a.consume(.videoIntent(job))
        #expect(a.consume(.done(usage)) == [
            .releaseVideoCredit(job),
            .completed(AssembledReply(inkText: "", usage: usage)),
        ])
    }

    @Test("a delivered clip is settled, not released")
    func deliveredVideoIsNotReleased() throws {
        var a = ReplyAssembler()
        let url = try #require(URL(string: "https://assets.inkwoven.app/vid-1.mp4"))
        _ = a.consume(.videoIntent(VideoJob(id: "vid-1")))
        #expect(a.consume(.videoFinal(url)) == [.playVideo(url)])
        #expect(a.pendingVideoJobs.isEmpty)
        #expect(a.consume(.done(usage)) == [
            .completed(AssembledReply(inkText: "", videoURL: url, usage: usage)),
        ])
    }

    @Test("abandon releases holds when the stream throws")
    func abandonReleasesHolds() {
        var a = ReplyAssembler()
        let job = VideoJob(id: "vid-1")
        _ = a.consume(.videoIntent(job))
        let first = a.abandon()
        let second = a.abandon()
        #expect(first == [.releaseVideoCredit(job)])
        #expect(second.isEmpty, "abandon is idempotent — never refund twice")
    }

    @Test("done materializes the assembled reply")
    func doneCompletes() {
        var a = ReplyAssembler()
        _ = a.consume(.inkDelta("Ask again at dusk."))
        let outputs = a.consume(.done(usage))
        #expect(outputs == [.completed(AssembledReply(inkText: "Ask again at dusk.", usage: usage))])
    }

    @Test("a failed develop closes its slot — the darkroom never spins forever")
    func imageFailureClosesSlot() {
        var a = ReplyAssembler()
        let job = ImageJob(id: "img-1")
        #expect(a.consume(.imageIntent(job)) == [.openDevelopSlot(job)])
        let failure = ImageFailure(id: "img-1", reason: "develop_failed")
        #expect(a.consume(.imageFailed(failure)) == [.closeDevelopSlot(failure)])
        // The ink stands: a failed develop never fails the exchange.
        let outputs = a.consume(.done(usage))
        #expect(outputs == [.completed(AssembledReply(inkText: "", imageURL: nil, usage: usage))])
    }
}
