import Foundation
import InkCore
import InkNet
import InkMoney
import InkAnalytics

/// Composition root. All cross-package boundaries are protocols; the live
/// implementations are bound here and nowhere else.
@Observable
@MainActor
final class AppDI {
    let proxy: ProxyClient
    let analytics: Analytics
    let keeperAuth: any KeeperAuthenticating
    let archive = PageArchive()

    init(proxy: ProxyClient, analytics: Analytics, keeperAuth: any KeeperAuthenticating) {
        self.proxy = proxy
        self.analytics = analytics
        self.keeperAuth = keeperAuth
    }

    static func live() -> AppDI {
        let endpoints = ProxyEndpoints(baseURL: proxyBaseURL())
        let proxy = ProxyClient(endpoints: endpoints, auth: AnonymousTokenProvider())
        // TODO(A3): bind the real SDK adapter here for both configurations.
        #if DEBUG
        let analytics = Analytics(sink: ConsoleAnalyticsSink())
        #else
        let analytics = Analytics(sink: NullAnalyticsSink())
        #endif
        return AppDI(proxy: proxy, analytics: analytics, keeperAuth: LiveKeeperAuth())
    }

    /// Deployed proxy (keys live there as fly secrets). The `INKWOVEN_PROXY_URL`
    /// override for local echo-mode development is read in DEBUG only, so a
    /// shipping build has no path to a cleartext local endpoint — and a
    /// malformed value degrades to production instead of trapping before the
    /// first frame, since this runs during App initialization.
    private static func proxyBaseURL() -> URL {
        #if DEBUG
        if let override = ProcessInfo.processInfo.environment["INKWOVEN_PROXY_URL"],
           let url = URL(string: override) {
            return url
        }
        #endif
        // Force-unwrapped on a compile-time literal only: this string is fixed
        // in source and provably parses. Nothing user- or environment-supplied
        // reaches it.
        return URL(string: "https://inkwoven-proxy.fly.dev")!
    }
}

/// Anonymous install token; App Attest assertion + Sign in with Apple upgrade
/// happen behind this same protocol (task F4). Held in the Keychain, not
/// UserDefaults: this value is the whole of the app's server-side identity,
/// and the proxy trusts it verbatim, so a plist readable from an unencrypted
/// backup is an account-takeover primitive.
struct AnonymousTokenProvider: AuthTokenProviding {
    private static let account = "ink.anonymous.user"

    func token() async throws -> String {
        if let existing = InkKeychain.string(for: Self.account) { return existing }
        // Migrate the pre-Keychain identity rather than minting a new one —
        // it is the key to the user's server-side wallet.
        if let legacy = UserDefaults.standard.string(forKey: Self.account) {
            if InkKeychain.set(legacy, for: Self.account) {
                UserDefaults.standard.removeObject(forKey: Self.account)
            }
            return legacy
        }
        let fresh = UUID().uuidString
        if !InkKeychain.set(fresh, for: Self.account) {
            // A per-request identity would be worse than a readable one: the
            // proxy would seed a fresh wallet every call. Fall back so the
            // token at least stays stable.
            UserDefaults.standard.set(fresh, forKey: Self.account)
        }
        return fresh
    }
}

/// Until the real SDK adapter binds (task A3), release builds send events
/// nowhere. `AnalyticsEvent.parameters` is a closed schema — no page, ink or
/// reply text can reach it — but `crisis_flow` alone is a mental-health signal
/// that must not sit in the unified log, readable by anyone who can pair with
/// the device.
struct NullAnalyticsSink: AnalyticsSink {
    func track(name: String, parameters: [String: AnalyticsValue]) {}
}

#if DEBUG
struct ConsoleAnalyticsSink: AnalyticsSink {
    func track(name: String, parameters: [String: AnalyticsValue]) {
        print("[analytics] \(name) \(parameters)")
    }
}
#endif
