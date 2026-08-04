import Foundation
import InkCore
import InkNet
import InkMoney
import InkAnalytics
import UserNotifications

/// Composition root. All cross-package boundaries are protocols; the live
/// implementations are bound here and nowhere else.
@Observable
@MainActor
final class AppDI {
    let proxy: ProxyClient
    let analytics: Analytics
    let keeperAuth: any KeeperAuthenticating
    let archive = PageArchive()
    /// Unsent ink between launches (audit D-1). Sibling of the archive: same
    /// directory discipline, same protection class, Keeper backup-excluded.
    let drafts = PageDraftStore()
    let ritual = RitualScheduler()
    /// Retained for the app's lifetime — the notification centre holds its
    /// delegate weakly, and a deallocated delegate silently drops the tap
    /// that should attribute an open to the ritual.
    private let ritualDelegate: RitualNotificationDelegate

    init(
        proxy: ProxyClient,
        analytics: Analytics,
        keeperAuth: any KeeperAuthenticating,
        wallet: (any WalletReading)? = nil
    ) {
        self.proxy = proxy
        self.analytics = analytics
        self.keeperAuth = keeperAuth
        self.wallet = wallet ?? proxy
        // Installed during App init so a cold launch from a notification tap
        // still reaches the delegate before the response is delivered.
        ritualDelegate = RitualNotificationDelegate(analytics: analytics)
        UNUserNotificationCenter.current().delegate = ritualDelegate
    }

    /// Reads the vial balance for the rooms. In Release this is the proxy and
    /// nothing else; in Debug it is the stand-in below, which falls back to a
    /// local purse when the server cannot be reached.
    let wallet: any WalletReading

    static func live() -> AppDI {
        let endpoints = ProxyEndpoints(baseURL: proxyBaseURL())
        // Identity is PROVED, not asserted (audit T3): App Attest trades a
        // Secure Enclave key for a server-minted, short-lived session token.
        // The anonymous provider stays as the fallback for hardware that
        // cannot attest — the proxy decides whether that is acceptable, and
        // in appattest mode it is not.
        let auth = AppAttestIdentity(endpoints: endpoints, fallback: AnonymousTokenProvider())
        let proxy = ProxyClient(endpoints: endpoints, auth: auth)
        // The vials are bought through StoreKit but spent from the server-side
        // wallet, so the purchase store needs a way to reach the proxy.
        #if DEBUG
        let wallet = DebugVialWallet(live: proxy)
        LiveCommerce.bind(delivery: wallet)
        // The Debug purse replaces only the vial delivery; subscription
        // proofs and the remote gate config still go to the real proxy.
        LiveCommerce.bindRemote(proxy: proxy)
        #else
        let wallet = proxy
        LiveCommerce.bind(proxy: proxy)
        #endif
        // First read of the server-tunable gate knobs; RootView re-reads on
        // every foreground. Failure keeps the compiled-in defaults.
        Task { await LiveCommerce.refreshGateConfig() }
        // TODO(A3): bind the real SDK adapter here for both configurations.
        #if DEBUG
        let analytics = Analytics(sink: ConsoleAnalyticsSink())
        #else
        let analytics = Analytics(sink: NullAnalyticsSink())
        #endif
        return AppDI(
            proxy: proxy, analytics: analytics, keeperAuth: LiveKeeperAuth(), wallet: wallet
        )
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

/// Legacy anonymous install token — now only the FALLBACK behind
/// `AppAttestIdentity` (audit T3), for hardware that cannot attest. Held in
/// the Keychain, not UserDefaults: on a proxy running in anonymous mode this
/// value is the whole of the app's server-side identity, so a plist readable
/// from an unencrypted backup would be an account-takeover primitive.
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

/// A purse that answers when the proxy cannot.
///
/// The Vials get designed, priced and demoed long before a server is reachable
/// from a simulator, and a shop that can only ever show "—" cannot be judged —
/// nor can a sandbox purchase be seen to land. This tries the real wallet
/// first and keeps a local one once that fails, so the whole loop is visible:
/// two gifted moments, buy a pack, watch the count rise.
///
/// **Debug only, and structurally so.** In a Release build this type does not
/// exist, so no shipped path can read a balance the server never issued or
/// credit a purchase the server never saw. That is the same reason the real
/// `grantVials` call is tried first here: when the proxy IS up, this behaves
/// exactly like production and the fallback never runs.
actor DebugVialWallet: WalletReading, VialGrantDelivering {
    private let live: ProxyClient
    /// Sticky: once the server has failed, stop paying its timeout on every
    /// read. Relaunch to try again.
    private var serverIsAbsent = false
    private var localCredits = 0
    private var localFreeClips = 2

    init(live: ProxyClient) { self.live = live }

    func wallet() async throws -> WalletView {
        if !serverIsAbsent {
            do { return try await live.wallet() } catch { serverIsAbsent = true }
        }
        return WalletView(
            balance: localCredits,
            available: localCredits,
            freeClipsRemaining: localFreeClips,
            freeClipsOpen: true
        )
    }

    func deliver(_ grant: VialGrant) async throws {
        if !serverIsAbsent {
            do {
                try await live.grantVials(VialGrantPayload(
                    productID: grant.productID,
                    transactionID: grant.transactionID,
                    jws: grant.jws
                ))
                return
            } catch {
                serverIsAbsent = true
            }
        }
        // The pack sizes are the client's copy of the server's map — fine for
        // a demo purse, never for a real one.
        localCredits += ProductID.creditAmount(for: grant.productID) ?? 0
        print("[vials] local purse credited \(grant.productID) → \(localCredits)")
    }
}
#endif
