import Foundation
import InkCore

public struct ProxyEndpoints: Sendable {
    public var baseURL: URL

    public init(baseURL: URL) { self.baseURL = baseURL }

    public var exchange: URL { baseURL.appending(path: "v1/exchange") }
    public var preupload: URL { baseURL.appending(path: "v1/preupload") }
    public func preuploadTicket(_ id: String) -> URL { preupload.appending(path: id) }
    public var books: URL { baseURL.appending(path: "v1/books") }
    public var config: URL { baseURL.appending(path: "v1/config") }
}

/// App-attest + anonymous user token; Sign in with Apple upgrades the token.
public protocol AuthTokenProviding: Sendable {
    func token() async throws -> String
}

/// Speculative-upload handle (task B2): `preupload` at ~2s of pen rest,
/// `exchange(ticket:)` attaches the model call at 3s, `abort` cancels.
/// The server never bills an uncommitted ticket.
public struct UploadTicket: Equatable, Sendable, Codable {
    public var id: String
    public var expiresAt: Date

    public init(id: String, expiresAt: Date) {
        self.id = id
        self.expiresAt = expiresAt
    }
}

struct ExchangeRequestBody: Encodable {
    var bookID: String
    var context: PageContext
    var snapshotBase64: String?
    var digest: String
    var ticketID: String?
}

public final class ProxyClient: Sendable {
    private let endpoints: ProxyEndpoints
    private let session: URLSession
    private let auth: any AuthTokenProviding

    public init(endpoints: ProxyEndpoints, session: URLSession = .shared, auth: any AuthTokenProviding) {
        self.endpoints = endpoints
        self.session = session
        self.auth = auth
    }

    /// One exchange: snapshot + book + context → chunk stream over SSE.
    /// The first `.inkDelta` must reach the renderer immediately (streaming-
    /// first); the caller owns an `ExchangeTimer` and stamps ttfs on it.
    /// Pass `ticket` when a speculative upload already carried the payload.
    public func exchange(
        payload: SnapshotPayload,
        book: BookID,
        context: PageContext,
        ticket: UploadTicket? = nil
    ) -> AsyncThrowingStream<ReplyChunk, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var attempt = 0
                while true {
                    // Set the instant the response headers are accepted. Past
                    // that point the attempt is unretryable by construction:
                    // it is the only boundary at which we can prove no chunk
                    // has been yielded, so no ink can re-stream and no `done`
                    // can be counted twice. See the guard below.
                    var committed = false
                    do {
                        // A retry never reuses the ticket — the server consumes
                        // it on first sight, so a second attempt carrying the
                        // same id would reach the Book with no snapshot at all.
                        let request = try await exchangeRequest(
                            payload: payload,
                            book: book,
                            context: context,
                            ticket: attempt == 0 ? ticket : nil
                        )
                        try await runAttempt(request, into: continuation) { committed = true }
                        continuation.finish()
                        return
                    } catch {
                        let proxy = Self.mapped(error)
                        guard !committed,
                              !Task.isCancelled,
                              RetryPolicy.shouldRetry(proxy, attempt: attempt) else {
                            continuation.finish(throwing: proxy)
                            return
                        }
                        do {
                            try await Task.sleep(for: .seconds(RetryPolicy.delay(beforeAttempt: attempt)))
                        } catch {
                            // Sleep only throws on cancellation — the reader
                            // left the page; do not open another connection.
                            continuation.finish(throwing: ProxyError.cancelled)
                            return
                        }
                        attempt += 1
                    }
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func exchangeRequest(
        payload: SnapshotPayload,
        book: BookID,
        context: PageContext,
        ticket: UploadTicket?
    ) async throws -> URLRequest {
        var request = URLRequest(url: endpoints.exchange)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue(try await auth.token(), forHTTPHeaderField: "x-ink-user")
        let body = ExchangeRequestBody(
            bookID: book.rawValue,
            context: context,
            snapshotBase64: ticket == nil ? payload.imageData.base64EncodedString() : nil,
            digest: payload.digest,
            ticketID: ticket?.id
        )
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    /// One attempt at the stream. `onCommit` fires the moment the response is
    /// accepted, before a single chunk can be yielded.
    private func runAttempt(
        _ request: URLRequest,
        into continuation: AsyncThrowingStream<ReplyChunk, Error>.Continuation,
        onCommit: () -> Void
    ) async throws {
        let (bytes, response) = try await session.bytes(for: request)
        try Self.check(response)
        onCommit()

        var parser = SSEParser()
        for try await byte in bytes {
            if let event = parser.consume(byte: byte),
               let chunk = ChunkDecoder.decode(event) {
                continuation.yield(chunk)
            }
        }
        // The stream can end without the blank line that terminates its last
        // event — a backgrounded device, a recycled edge node. Recover it
        // rather than reporting a fully-received reply as a decline.
        if let event = parser.flush(), let chunk = ChunkDecoder.decode(event) {
            continuation.yield(chunk)
        }
    }

    public func preupload(_ payload: SnapshotPayload) async throws -> UploadTicket {
        var request = URLRequest(url: endpoints.preupload)
        request.httpMethod = "POST"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.setValue(payload.digest, forHTTPHeaderField: "x-ink-digest")
        request.setValue(try await auth.token(), forHTTPHeaderField: "x-ink-user")
        request.httpBody = payload.imageData
        do {
            let (data, response) = try await session.data(for: request)
            try Self.check(response)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(UploadTicket.self, from: data)
        } catch {
            throw Self.mapped(error)
        }
    }

    /// Abort is best-effort: the ticket expires server-side regardless, and an
    /// uncommitted ticket is never billed.
    public func abort(_ ticket: UploadTicket) async {
        var request = URLRequest(url: endpoints.preuploadTicket(ticket.id))
        request.httpMethod = "DELETE"
        if let token = try? await auth.token() {
            request.setValue(token, forHTTPHeaderField: "x-ink-user")
        }
        _ = try? await session.data(for: request)
    }

    static func check(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw ProxyError.badResponse }
        switch http.statusCode {
        case 200...299:
            return
        case 422:
            throw ProxyError.moderated
        case 429:
            throw ProxyError.rateLimited(retryAfterSeconds: Self.retryAfter(http))
        default:
            throw ProxyError.server(status: http.statusCode)
        }
    }

    /// RFC 7231 allows `Retry-After` as delta-seconds *or* an HTTP-date; any
    /// CDN or WAF in front of the proxy may emit the date form, and reading it
    /// as nil would cost the page its cooldown.
    static func retryAfter(_ http: HTTPURLResponse, now: Date = Date()) -> Double? {
        guard let raw = http.value(forHTTPHeaderField: "Retry-After")?
            .trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }
        if let seconds = Double(raw) { return max(0, seconds) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        guard let date = formatter.date(from: raw) else { return nil }
        return max(0, date.timeIntervalSince(now))
    }

    private static func mapped(_ error: Error) -> ProxyError {
        switch error {
        case let proxy as ProxyError:
            return proxy
        case is CancellationError:
            return .cancelled
        case let url as URLError where url.code == .cancelled:
            return .cancelled
        case let url as URLError where url.code == .notConnectedToInternet || url.code == .networkConnectionLost:
            return .offline
        case let url as URLError:
            return .transport(url.code.rawValue.description)
        default:
            return .transport(String(describing: type(of: error)))
        }
    }
}
