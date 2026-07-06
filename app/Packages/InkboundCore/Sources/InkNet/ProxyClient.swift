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
                do {
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

                    let (bytes, response) = try await session.bytes(for: request)
                    try Self.check(response)

                    var parser = SSEParser()
                    for try await byte in bytes {
                        if let event = parser.consume(byte: byte),
                           let chunk = ChunkDecoder.decode(event) {
                            continuation.yield(chunk)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: Self.mapped(error))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
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

    private static func check(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw ProxyError.badResponse }
        switch http.statusCode {
        case 200...299:
            return
        case 422:
            throw ProxyError.moderated
        case 429:
            let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init)
            throw ProxyError.rateLimited(retryAfterSeconds: retryAfter)
        default:
            throw ProxyError.server(status: http.statusCode)
        }
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
