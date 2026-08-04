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
    public var report: URL { baseURL.appending(path: "v1/report") }
    public var video: URL { baseURL.appending(path: "v1/video") }
    public var credits: URL { baseURL.appending(path: "v1/credits") }
    public var creditsGrant: URL { credits.appending(path: "grant") }
    public var entitlement: URL { baseURL.appending(path: "v1/entitlement") }
    // App Attest (audit T3): the routes that MAKE an identity, so they run
    // before one exists and carry no x-ink-user of their own.
    public var attestChallenge: URL { baseURL.appending(path: "v1/attest/challenge") }
    public var attest: URL { baseURL.appending(path: "v1/attest") }
    public var attestRefresh: URL { baseURL.appending(path: "v1/attest/refresh") }
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

/// A user-triggered request for a moving picture (task J4). The client names
/// the brief the Book produced and mints its own job id; it never supplies
/// prompt text, and it never names a price — what a clip costs, and whether
/// this one is free, is the proxy's decision.
///
/// `videoID` is the idempotency key: a double-tap, a retry, or a relaunch that
/// re-asks for the same clip all resolve to one generation and one charge.
struct VideoRequestBody: Encodable {
    var briefID: String
    var videoID: String
}

/// What the wallet holds, as the proxy reports it. Free clips ride along so
/// the affordance can be honest about what a tap spends before it commits.
public struct WalletView: Equatable, Sendable, Codable {
    public var balance: Int
    public var available: Int
    public var freeClipsRemaining: Int
    public var freeClipsOpen: Bool

    public init(balance: Int, available: Int, freeClipsRemaining: Int, freeClipsOpen: Bool) {
        self.balance = balance
        self.available = available
        self.freeClipsRemaining = freeClipsRemaining
        self.freeClipsOpen = freeClipsOpen
    }

    /// What the next clip would spend. The proxy makes the real decision — this
    /// only decides which sentence the page shows before the tap.
    public var nextClipIsFree: Bool { freeClipsRemaining > 0 && freeClipsOpen }
    public var canAffordClip: Bool { nextClipIsFree || available > 0 }
}

/// A verified consumable purchase, forwarded so the server-side wallet can
/// credit it. StoreKit verified the transaction on device; the amount is the
/// proxy's to decide from the product id.
public struct VialGrantPayload: Equatable, Sendable, Encodable {
    public var productID: String
    public var transactionID: String
    public var jws: String

    public init(productID: String, transactionID: String, jws: String) {
        self.productID = productID
        self.transactionID = transactionID
        self.jws = jws
    }
}

/// A verified subscription receipt, forwarded so the server can widen this
/// identity's daily exchange quota (audit M-2). Without it every identity
/// meters as free server-side; the proxy re-verifies the JWS itself.
public struct EntitlementProofPayload: Equatable, Sendable, Encodable {
    public var productID: String
    public var transactionID: String
    public var jws: String

    public init(productID: String, transactionID: String, jws: String) {
        self.productID = productID
        self.transactionID = transactionID
        self.jws = jws
    }
}

/// Server-tunable gate knobs as `GET /v1/config` serves them — the wire twin
/// of `InkMoney.GateConfig`, which InkNet cannot see (both packages stand on
/// InkCore alone). The App layer maps one into the other. Extra keys in the
/// server's CONFIG are ignored by decoding.
public struct RemoteGateConfig: Equatable, Sendable, Codable {
    public var freeMomentsPerDay: Int
    public var plusImageDailySoftCap: Int
    public var cooldownCurveSeconds: [Double]

    public init(freeMomentsPerDay: Int, plusImageDailySoftCap: Int, cooldownCurveSeconds: [Double]) {
        self.freeMomentsPerDay = freeMomentsPerDay
        self.plusImageDailySoftCap = plusImageDailySoftCap
        self.cooldownCurveSeconds = cooldownCurveSeconds
    }
}

/// One user-triggered report of a reply (guideline 1.2). Assembled only at
/// the moment the user taps send — reporting is a cold path, fully apart
/// from the exchange, and nothing is ever queued or sent in the background.
/// `reportID` is minted client-side and doubles as the server's idempotency
/// key, so a retried or double-tapped send files exactly one report.
public struct ReportPayload: Equatable, Sendable, Encodable {
    public var reportID: UUID
    public var replyID: UUID
    public var pageID: UUID
    public var bookID: String
    public var reason: String
    public var note: String?
    public var replyKind: String
    public var replyText: String?
    public var assetRef: String?
    public var modelID: String
    public var snapshotDigest: String
    public var snapshotBase64: String
    public var createdAt: Date
    public var submittedAt: Date

    public init(
        reportID: UUID,
        replyID: UUID,
        pageID: UUID,
        bookID: String,
        reason: String,
        note: String?,
        replyKind: String,
        replyText: String?,
        assetRef: String?,
        modelID: String,
        snapshotDigest: String,
        snapshotBase64: String,
        createdAt: Date,
        submittedAt: Date
    ) {
        self.reportID = reportID
        self.replyID = replyID
        self.pageID = pageID
        self.bookID = bookID
        self.reason = reason
        self.note = note
        self.replyKind = replyKind
        self.replyText = replyText
        self.assetRef = assetRef
        self.modelID = modelID
        self.snapshotDigest = snapshotDigest
        self.snapshotBase64 = snapshotBase64
        self.createdAt = createdAt
        self.submittedAt = submittedAt
    }
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
        // Client-side deadline (audit D-8): the server's 120s stream deadline
        // is real, but trusting it ENTIRELY left a page stuck at "sending"
        // forever when the connection died silently. The server heartbeats
        // every 15s, so this idle timeout only fires when nothing — not even
        // a heartbeat — has arrived for longer than the whole server window.
        request.timeoutInterval = 150
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

    /// One moving picture, requested because the reader tapped (task J4).
    ///
    /// The stream is the wait: generation takes minutes, so the server
    /// heartbeats and the chunks (`videoIntent` → `videoFinal` / `videoFailed`)
    /// arrive as they happen. Deliberately NOT retried: a retry here is a
    /// second generation, and the money-safe retry is the caller re-asking with
    /// the same `videoID`, which the server resolves to one clip and one charge.
    public func video(
        briefID: String,
        videoID: UUID
    ) -> AsyncThrowingStream<ReplyChunk, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = URLRequest(url: endpoints.video)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    request.setValue(try await auth.token(), forHTTPHeaderField: "x-ink-user")
                    // A clip outlasts the default resource timeout; the server
                    // owns the real deadline and answers with an event.
                    request.timeoutInterval = 420
                    request.httpBody = try JSONEncoder().encode(
                        VideoRequestBody(briefID: briefID, videoID: videoID.uuidString)
                    )
                    try await runAttempt(request, into: continuation) {}
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: Self.mapped(error))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// The wallet as the server sees it, including the free-clip balance.
    public func wallet() async throws -> WalletView {
        var request = URLRequest(url: endpoints.credits)
        request.setValue(try await auth.token(), forHTTPHeaderField: "x-ink-user")
        do {
            let (data, response) = try await session.data(for: request)
            try Self.check(response)
            return try JSONDecoder().decode(WalletView.self, from: data)
        } catch {
            throw Self.mapped(error)
        }
    }

    /// The server-tunable gate knobs, fetched at launch and on foreground so
    /// cap and cooldown changes ship without an app release. Before this call
    /// existed, `GateConfig` always ran on compiled-in defaults and the
    /// "tunable without a release" promise in the proxy's config was not real.
    public func gateConfig() async throws -> RemoteGateConfig {
        var request = URLRequest(url: endpoints.config)
        request.setValue(try await auth.token(), forHTTPHeaderField: "x-ink-user")
        do {
            let (data, response) = try await session.data(for: request)
            try Self.check(response)
            return try JSONDecoder().decode(RemoteGateConfig.self, from: data)
        } catch {
            throw Self.mapped(error)
        }
    }

    /// Forwards a verified subscription receipt so the server-side quota
    /// meters this identity as Plus (audit M-2). Best-effort by design: the
    /// caller ignores failures — the client's own gate still runs, this only
    /// widens the server backstop.
    public func attestEntitlement(_ payload: EntitlementProofPayload) async throws {
        var request = URLRequest(url: endpoints.entitlement)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(try await auth.token(), forHTTPHeaderField: "x-ink-user")
        request.httpBody = try JSONEncoder().encode(payload)
        do {
            let (_, response) = try await session.data(for: request)
            try Self.check(response)
        } catch {
            throw Self.mapped(error)
        }
    }

    /// Forwards a verified consumable purchase so the server can credit it.
    /// The transaction id is the idempotency key, so re-sending a receipt the
    /// server already honoured credits nothing further.
    public func grantVials(_ payload: VialGrantPayload) async throws {
        var request = URLRequest(url: endpoints.creditsGrant)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(try await auth.token(), forHTTPHeaderField: "x-ink-user")
        request.setValue(payload.transactionID, forHTTPHeaderField: "Idempotency-Key")
        request.httpBody = try JSONEncoder().encode(payload)
        do {
            let (_, response) = try await session.data(for: request)
            try Self.check(response)
        } catch {
            throw Self.mapped(error)
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

    /// Files a user-triggered report of a reply. The server answers with a
    /// small ack and never echoes content; failures map to the same
    /// ProxyError taxonomy so the sheet can fail in-fiction and retry.
    public func report(_ payload: ReportPayload) async throws {
        var request = URLRequest(url: endpoints.report)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(try await auth.token(), forHTTPHeaderField: "x-ink-user")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        request.httpBody = try encoder.encode(payload)
        do {
            let (_, response) = try await session.data(for: request)
            try Self.check(response)
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
        case 402:
            throw ProxyError.paymentRequired
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
