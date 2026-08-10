import Foundation
import InkCore
import InkNet
import InkMoney
import InkAnalytics
import RevenueCat
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

    /// Routes a tapped ritual night to its Book (audit L-18). Bound by the
    /// App the moment the model exists; the delegate holds a cold-launch tap
    /// until then. The route runs through `AppModel.openFromRitual`, whose
    /// open flow is where the Keeper's gate is enforced — never around it.
    func routeRitualTaps(to model: AppModel) {
        ritualDelegate.bind { [weak model] book in
            model?.openFromRitual(book)
        }
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
        // Before anything can touch `LiveCommerce.purchases`, which is a lazily
        // initialised static that both AppModel and the send gate resolve through.
        configureRevenueCat(auth: auth)
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
        // Sweep any export residue an abnormal exit left behind (audit L-22):
        // the purge otherwise runs only around a share, and a force-quit with
        // the sheet up leaves the journal's plaintext sitting in tmp. In a
        // task so it never taxes the first frame.
        Task { PageExporter.purge() }
        #if DEBUG
        let analytics = Analytics(sink: ConsoleAnalyticsSink())
        #else
        let analytics = Analytics(sink: NullAnalyticsSink())
        #endif
        return AppDI(
            proxy: proxy, analytics: analytics, keeperAuth: LiveKeeperAuth(), wallet: wallet
        )
    }

    /// The public, app-specific SDK key from RevenueCat (Platforms → Inkwoven).
    ///
    /// Public by design and safe in the binary: it can read offerings and post
    /// purchases for the customer using it, and nothing else. The `sk_` secret key
    /// is the proxy's alone and must never appear in this target — the reverse is
    /// equally true, the server has no business holding this one.
    private static let revenueCatAPIKey = "appl_BmDuZDoiugguNdjeHMjZbxMaBNU"

    /// Binds RevenueCat, in the mode `LiveCommerce.backend` implies.
    ///
    /// While the backend is `.storeKit`, RevenueCat is configured `.myApp`: it
    /// records purchases and owns none of them. That distinction is not cosmetic —
    /// in the default `.revenueCat` mode the SDK subscribes to
    /// `StoreKit.Transaction.updates` and finishes transactions it did not start,
    /// including the consumables `StoreKitEntitlementStore` deliberately leaves
    /// unfinished until the proxy has credited them. Configuring the wrong mode
    /// here silently removes the redelivery net that stops a user paying for vials
    /// they never receive.
    private static func configureRevenueCat(auth: AppAttestIdentity) {
        #if DEBUG
        Purchases.logLevel = .info
        #else
        Purchases.logLevel = .warn
        #endif
        let builder = Configuration.builder(withAPIKey: revenueCatAPIKey)
        switch LiveCommerce.backend {
        case .storeKit:
            builder.with(purchasesAreCompletedBy: .myApp, storeKitVersion: .storeKit2)
        case .revenueCat:
            builder.with(purchasesAreCompletedBy: .revenueCat, storeKitVersion: .storeKit2)
        }
        Purchases.configure(with: builder.build())

        // Identity is claimed AFTER configure rather than passed into it, because
        // the proxy mints it over the network and the first frame must not wait on
        // a handshake. RevenueCat starts on an anonymous id and aliases it to this
        // one; the alias is exactly what makes a purchase made in the first seconds
        // still belong to the right customer.
        //
        // The id must equal the proxy's own userID or a RevenueCat webhook cannot
        // find the wallet it is meant to credit.
        Task {
            guard let token = try? await auth.token() else { return }
            _ = try? await Purchases.shared.logIn(proxyUserID(from: token))
        }
    }

    /// The proxy's identity for this install, read from the token it issued.
    ///
    /// In `appattest` mode the token is a signed JWT whose `sub` is the server-minted
    /// userID; in the anonymous fallback the token *is* the userID (`proxy/src/attest.js`).
    /// Reading the claim without verifying it is correct here and only here: this
    /// value is used to name a RevenueCat customer, never to authorise anything.
    /// The proxy verifies the same token on every request it actually matters for.
    static func proxyUserID(from token: String) -> String {
        let segments = token.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count == 3 else { return token }
        var base64 = String(segments[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        guard let data = Data(base64Encoded: base64),
              let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let subject = claims["sub"] as? String, !subject.isEmpty
        else { return token }
        return subject
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
