import Foundation
import Testing
@testable import InkNet

@Suite("ProxyClient response mapping")
struct ProxyClientTests {
    private func response(_ status: Int, headers: [String: String] = [:]) throws -> HTTPURLResponse {
        let url = try #require(URL(string: "https://proxy.inkwoven.app/v1/exchange"))
        return try #require(HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers))
    }

    @Test("2xx passes, non-HTTP responses are a bad response")
    func statusBasics() throws {
        #expect(throws: Never.self) { try ProxyClient.check(try self.response(200)) }
        let url = try #require(URL(string: "https://proxy.inkwoven.app"))
        #expect(throws: ProxyError.badResponse) {
            try ProxyClient.check(URLResponse(url: url, mimeType: nil, expectedContentLength: 0, textEncodingName: nil))
        }
    }

    @Test("422 is a moderation decline, other statuses stay generic server faults")
    func statusMapping() throws {
        #expect(throws: ProxyError.moderated) { try ProxyClient.check(try self.response(422)) }
        #expect(throws: ProxyError.server(status: 500)) { try ProxyClient.check(try self.response(500)) }
    }

    @Test("429 carries Retry-After as delta-seconds")
    func retryAfterSeconds() throws {
        #expect(throws: ProxyError.rateLimited(retryAfterSeconds: 60)) {
            try ProxyClient.check(try self.response(429, headers: ["retry-after": "60"]))
        }
        #expect(throws: ProxyError.rateLimited(retryAfterSeconds: nil)) {
            try ProxyClient.check(try self.response(429))
        }
    }

    @Test("Retry-After also accepts the RFC 7231 HTTP-date form a CDN may emit")
    func retryAfterHTTPDate() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let http = try response(429, headers: ["Retry-After": "Tue, 14 Nov 2023 22:14:20 GMT"])
        let seconds = try #require(ProxyClient.retryAfter(http, now: now))
        #expect(seconds == 60)
    }

    @Test("a Retry-After in the past clamps to zero rather than going negative")
    func retryAfterPast() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let http = try response(429, headers: ["Retry-After": "Tue, 14 Nov 2023 22:00:00 GMT"])
        #expect(ProxyClient.retryAfter(http, now: now) == 0)
        #expect(ProxyClient.retryAfter(try response(429, headers: ["Retry-After": "-5"]), now: now) == 0)
    }

    @Test("an unparseable Retry-After degrades to nil rather than throwing")
    func retryAfterGarbage() throws {
        #expect(ProxyClient.retryAfter(try response(429, headers: ["Retry-After": "soon"])) == nil)
        #expect(ProxyClient.retryAfter(try response(429, headers: ["Retry-After": "  "])) == nil)
    }
}
