import CryptoKit
import DeviceCheck
import Foundation
import OSLog
import InkNet

/// The device's identity with the proxy (audit T3/M-3).
///
/// The token this replaces was a locally minted UUID the server took at face
/// value: any string under 256 characters was an account with its own wallet
/// and its own free-clip allowance, so every per-user limit was decorative.
/// Here the device generates an App Attest key in the Secure Enclave, proves
/// it against a server-issued challenge, and receives a SERVER-MINTED
/// identity carried by a short-lived signed session token. Renewal is by
/// assertion — the key signs a fresh challenge — so a captured token expires
/// into uselessness rather than becoming a permanent bearer secret.
///
/// Falls back to the legacy anonymous token when App Attest is unsupported
/// (the simulator, an old device) or when the PROXY offers no handshake at
/// all — the proxy is what decides whether that is acceptable, and in
/// `appattest` mode it simply is not. Nothing here grants itself anything.
actor AppAttestIdentity: AuthTokenProviding {
    private let service: DCAppAttestService
    private let endpoints: ProxyEndpoints
    private let session: URLSession
    private let fallback: any AuthTokenProviding

    /// The Secure Enclave key id, kept so a reinstall re-proves the SAME key
    /// and finds its existing wallet rather than minting a new identity.
    private static let keyIDAccount = "ink.appattest.keyID"

    private var cachedToken: String?
    private var cachedExpiry: Date?
    /// One in-flight handshake at a time: a cold launch fires several
    /// requests at once, and each would otherwise attest separately.
    private var inFlight: Task<String, Error>?
    /// This deployment has no handshake to complete (see `AttestationNotOffered`).
    /// Remembered for the process so every subsequent request does not pay a
    /// round-trip to a route that will not answer; a redeployed proxy is
    /// picked up on the next launch.
    private var attestationNotOffered = false

    private static let log = Logger(subsystem: "com.empath.inkwoven", category: "attest")

    init(
        endpoints: ProxyEndpoints,
        session: URLSession = .shared,
        fallback: any AuthTokenProviding,
        service: DCAppAttestService = .shared
    ) {
        self.endpoints = endpoints
        self.session = session
        self.fallback = fallback
        self.service = service
    }

    func token() async throws -> String {
        // A token good for another half-minute is good enough for this call;
        // renewing inside that window only risks a request racing an expiry.
        if let cachedToken, let cachedExpiry, cachedExpiry.timeIntervalSinceNow > 30 {
            return cachedToken
        }
        if let inFlight { return try await inFlight.value }
        let task = Task { try await handshake() }
        inFlight = task
        defer { inFlight = nil }
        return try await task.value
    }

    private func handshake() async throws -> String {
        guard service.isSupported, !attestationNotOffered else {
            // Simulator or unsupported hardware, or a proxy with no handshake
            // to complete. The proxy decides what this is worth; in appattest
            // mode it is worth nothing.
            return try await fallback.token()
        }
        do {
            if let keyID = InkKeychain.string(for: Self.keyIDAccount) {
                return try await refresh(keyID: keyID)
            }
            return try await attestFresh()
        } catch is AttestationNotOffered {
            // Not a rejection of this device — there is simply nothing here to
            // attest against. Carry on with the legacy identity and let the
            // proxy judge it, rather than leaving the app with no identity at
            // all and every page declining as "the spirit is distant".
            Self.log.notice("proxy offers no App Attest handshake; using the anonymous identity")
            attestationNotOffered = true
            return try await fallback.token()
        } catch {
            Self.log.error("attestation failed: \(String(describing: error), privacy: .public)")
            throw error
        }
    }

    /// The proxy has no handshake to complete. Distinct from a rejection: the
    /// attest routes are absent (404 — a proxy older than the attest work),
    /// gated behind the very identity they exist to mint (401 — the same
    /// vintage, whose auth hook has no exemption for routes it does not know
    /// about), or present with an unbound verifier (501). This device is not
    /// what any of those three are about.
    private struct AttestationNotOffered: Error {}

    /// First run: generate a key, attest it, receive the minted identity.
    private func attestFresh() async throws -> String {
        // The challenge comes FIRST so a proxy that offers no handshake is
        // discovered before a Secure Enclave key is minted for it and thrown
        // away — `generateKey` needs nothing from the challenge.
        let challenge = try await requestChallenge()
        let keyID = try await service.generateKey()
        let attestation = try await service.attestKey(
            keyID, clientDataHash: Data(SHA256.hash(data: challenge))
        )
        let token = try await post(
            endpoints.attest,
            body: ["keyID": keyID, "attestation": attestation.base64EncodedString(),
                   "challenge": challenge.base64EncodedString()]
        )
        InkKeychain.set(keyID, for: Self.keyIDAccount)
        return token
    }

    /// Later runs: the stored key signs a fresh challenge. A rejected key
    /// (revoked, re-installed OS, server-side reset) attests anew rather than
    /// leaving the app with no identity at all.
    private func refresh(keyID: String) async throws -> String {
        let challenge = try await requestChallenge()
        let clientDataHash = Data(SHA256.hash(data: challenge))
        let assertion = try await service.generateAssertion(keyID, clientDataHash: clientDataHash)
        do {
            return try await post(
                endpoints.attestRefresh,
                body: ["keyID": keyID, "assertion": assertion.base64EncodedString(),
                       "challenge": challenge.base64EncodedString()]
            )
        } catch ProxyError.server(let status) where status == 401 {
            InkKeychain.remove(account: Self.keyIDAccount)
            return try await attestFresh()
        }
    }

    /// The challenge is also the probe: it is the first thing every handshake
    /// asks for, and the one step a correctly configured proxy answers without
    /// an identity — so it is where "this deployment does not do attestation"
    /// is cheapest and least ambiguous to read.
    private func requestChallenge() async throws -> Data {
        var request = URLRequest(url: endpoints.attestChallenge)
        request.httpMethod = "POST"
        let (data, response) = try await session.data(for: request)
        do {
            try Self.check(response)
        } catch ProxyError.server(let status) where status == 401 || status == 404 || status == 501 {
            throw AttestationNotOffered()
        }
        struct ChallengeResponse: Decodable { let challenge: String }
        let decoded = try JSONDecoder().decode(ChallengeResponse.self, from: data)
        guard let raw = Data(base64Encoded: decoded.challenge) else {
            throw ProxyError.badResponse
        }
        return raw
    }

    /// Posts an attestation or assertion and caches the session token it
    /// returns. The expiry is the server's — the client never extends it.
    private func post(_ url: URL, body: [String: String]) async throws -> String {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await session.data(for: request)
        try Self.check(response)
        struct TokenResponse: Decodable {
            let token: String
            let expiresAt: Date
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(TokenResponse.self, from: data)
        cachedToken = decoded.token
        cachedExpiry = decoded.expiresAt
        return decoded.token
    }

    private static func check(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw ProxyError.badResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw ProxyError.server(status: http.statusCode)
        }
    }
}
