import Foundation
import Testing
import InkCore
import InkNet
@testable import InkSafety

@Suite("Crisis preemption (task F1)")
struct CrisisTests {
    let payload = CrisisPayload(message: "You matter.", resources: [.init(name: "988 Lifeline", contact: "988")])

    /// Fixture chunk streams for all 8 Books — crisis must preempt everywhere,
    /// including the GM mid-dark-scene and the Tutor mid-frustration.
    private func bookStream(for book: BookID) -> [ReplyChunk] {
        switch book {
        case .gameMaster:
            [.inkDelta("The blade falls toward"), .crisis(payload), .inkDelta(" your throat"), .imageIntent(ImageJob(id: "grim"))]
        case .tutor:
            [.inkDelta("Not quite — try again"), .crisis(payload), .inkDelta(", carry the 2")]
        case .artist:
            [.imageIntent(ImageJob(id: "sketch")), .crisis(payload), .imagePreview(Data([0x01]))]
        default:
            [.inkDelta("The page listens."), .crisis(payload), .inkDelta("more fiction"), .done(Usage(modelID: "m", inputTokens: 1, outputTokens: 1))]
        }
    }

    @Test("crisis mid-stream: renderer sees nothing after the crisis chunk", arguments: BookID.launchShelf)
    func crisisPreemptsInEveryBook(book: BookID) async throws {
        let upstream = AsyncThrowingStream<ReplyChunk, Error> { continuation in
            for chunk in bookStream(for: book) { continuation.yield(chunk) }
            continuation.finish()
        }

        var received: [ReplyChunk] = []
        for try await chunk in CrisisInterceptor.intercept(upstream) {
            received.append(chunk)
        }

        let crisisIndex = try #require(received.firstIndex(of: .crisis(payload)))
        #expect(crisisIndex == received.count - 1, "the crisis chunk terminates the stream immediately")
    }

    @Test("CrisisGuard discards everything after preemption")
    func guardDiscardsAfterPreemption() {
        var guardState = CrisisGuard()
        #expect(guardState.inspect(.inkDelta("hello")) == .passthrough(.inkDelta("hello")))
        #expect(guardState.inspect(.crisis(payload)) == .preempt(payload))
        #expect(guardState.inspect(.inkDelta("after")) == .discard)
        #expect(guardState.inspect(.done(Usage(modelID: "m", inputTokens: 0, outputTokens: 0))) == .discard)
    }

    @Test("a preempted exchange is not billed as a moment")
    func crisisNotBilled() {
        #expect(!MomentBilling.isBillable([.inkDelta("x"), .crisis(payload)]))
        #expect(MomentBilling.isBillable([.inkDelta("x"), .done(Usage(modelID: "m", inputTokens: 0, outputTokens: 0))]))
    }

    @Test("streams without crisis pass through untouched")
    func cleanStreamPassesThrough() async throws {
        let chunks: [ReplyChunk] = [.inkDelta("a"), .inkDelta("b"), .done(Usage(modelID: "m", inputTokens: 1, outputTokens: 1))]
        let upstream = AsyncThrowingStream<ReplyChunk, Error> { continuation in
            for chunk in chunks { continuation.yield(chunk) }
            continuation.finish()
        }
        var received: [ReplyChunk] = []
        for try await chunk in CrisisInterceptor.intercept(upstream) { received.append(chunk) }
        #expect(received == chunks)
    }
}

@Suite("In-fiction decline mapping (tasks C6/F2)")
struct DeclineMapperTests {
    @Test("moderation → soft decline, never auto-retried, no category detail")
    func moderationSoftDeclines() {
        #expect(DeclineMapper.map(.moderated) == .pageDeclines)
        #expect(!DeclineMapper.mayAutoRetry(.moderated))
    }

    @Test("rate limit → the ink must rest")
    func rateLimitRests() {
        #expect(DeclineMapper.map(.rateLimited(retryAfterSeconds: 30)) == .inkMustRest(seconds: 30))
    }

    @Test("offline → the page is quiet; transport may retry")
    func offlineQuiet() {
        #expect(DeclineMapper.map(.offline) == .pageIsQuiet)
        #expect(DeclineMapper.mayAutoRetry(.offline))
        #expect(DeclineMapper.mayAutoRetry(.transport("reset")))
    }
}
