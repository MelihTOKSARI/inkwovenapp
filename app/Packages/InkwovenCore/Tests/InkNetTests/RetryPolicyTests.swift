import Foundation
import Testing
@testable import InkNet

@Suite("RetryPolicy")
struct RetryPolicyTests {
    @Test("transport failures retry, up to 2 attempts")
    func transportRetries() {
        #expect(RetryPolicy.shouldRetry(.transport("timeout"), attempt: 0))
        #expect(RetryPolicy.shouldRetry(.offline, attempt: 1))
        #expect(!RetryPolicy.shouldRetry(.transport("timeout"), attempt: 2))
    }

    @Test("moderation rejections are never retried")
    func moderationNeverRetries() {
        #expect(!RetryPolicy.shouldRetry(.moderated, attempt: 0))
    }

    @Test("server errors and rate limits are not transport — no retry")
    func applicationErrorsNoRetry() {
        #expect(!RetryPolicy.shouldRetry(.server(status: 500), attempt: 0))
        #expect(!RetryPolicy.shouldRetry(.rateLimited(retryAfterSeconds: 30), attempt: 0))
        #expect(!RetryPolicy.shouldRetry(.cancelled, attempt: 0))
    }

    @Test("backoff is exponential")
    func exponentialBackoff() {
        #expect(RetryPolicy.delay(beforeAttempt: 0) == 0.5)
        #expect(RetryPolicy.delay(beforeAttempt: 1) == 1.0)
    }
}

@Suite("ExchangeTimer")
struct ExchangeTimerTests {
    @Test("time-to-first-stroke stamps once and reports ms")
    func ttfsStampsOnce() {
        let sent = Date(timeIntervalSinceReferenceDate: 0)
        var timer = ExchangeTimer(sentAt: sent)
        #expect(timer.ttfsMS == nil)

        let first = timer.markFirstChunk(at: sent.addingTimeInterval(1.234))
        #expect(first == 1234)

        // Later chunks must not move the stamp.
        let second = timer.markFirstChunk(at: sent.addingTimeInterval(9))
        #expect(second == nil)
        #expect(timer.ttfsMS == 1234)
    }
}
