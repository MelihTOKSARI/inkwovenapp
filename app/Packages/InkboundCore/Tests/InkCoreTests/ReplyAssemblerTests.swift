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
        let url = try #require(URL(string: "https://assets.inkbound.app/img-1.jpg"))

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

    @Test("done materializes the assembled reply")
    func doneCompletes() {
        var a = ReplyAssembler()
        _ = a.consume(.inkDelta("Ask again at dusk."))
        let outputs = a.consume(.done(usage))
        #expect(outputs == [.completed(AssembledReply(inkText: "Ask again at dusk.", usage: usage))])
    }
}
