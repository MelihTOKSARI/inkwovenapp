import Foundation
import InkCore
import InkMoney
import InkNet

/// Carries a verified vial purchase to the server-side wallet.
///
/// This is the only place the two halves of commerce meet: StoreKit proves the
/// purchase, the proxy owns the balance. Throwing propagates — `PurchaseService`
/// reads a throw as "leave the transaction unfinished", which is what makes a
/// failed delivery a retry rather than a loss.
struct ProxyVialDelivery: VialGrantDelivering {
    let proxy: ProxyClient

    func deliver(_ grant: VialGrant) async throws {
        try await proxy.grantVials(VialGrantPayload(
            productID: grant.productID,
            transactionID: grant.transactionID,
            jws: grant.jws
        ))
    }
}

/// Proves a Plus subscription to the proxy so the server-side daily quota
/// meters this identity correctly (audit M-2). The server re-verifies the JWS;
/// this only carries it.
struct ProxyPlusAttestor: PlusAttesting {
    let proxy: ProxyClient

    func attest(_ proof: EntitlementProof) async throws {
        try await proxy.attestEntitlement(EntitlementProofPayload(
            productID: proof.productID,
            transactionID: proof.transactionID,
            jws: proof.jws
        ))
    }
}

/// The server-tunable gate knobs, as last fetched. Defaults stand until the
/// first `GET /v1/config` answers — offline the gate simply runs on the
/// compiled-in numbers, which mirror the server's.
actor GateConfigStore {
    private(set) var current = GateConfig()

    func update(_ next: GateConfig) {
        current = next
    }
}

/// The one live commerce composition.
///
/// These bindings belong in `App/DI.swift` — the composition root — and moving
/// them there is a four-line change (see the handoff note). Until then they
/// live here as a single shared instance, because the alternative is worse:
/// `AppModel.bound` and the page's send gate reading two different receipts and
/// two different counters.
enum LiveCommerce {
    /// Bound once the app's proxy client exists (`AppDI.live()`); until then a
    /// consumable purchase stays unfinished rather than being consumed with
    /// nowhere to deliver it.
    nonisolated(unsafe) private static var delivery: (any VialGrantDelivering)?
    /// Bound alongside: where subscription proofs go (audit M-2). Nil until
    /// the proxy exists; a missed attempt re-proves on the next refresh.
    nonisolated(unsafe) private static var attestor: (any PlusAttesting)?
    /// Fetches `GET /v1/config`; nil until the proxy exists.
    nonisolated(unsafe) private static var configFetch: (@Sendable () async throws -> RemoteGateConfig)?

    static func bind(proxy: ProxyClient) {
        delivery = ProxyVialDelivery(proxy: proxy)
        bindRemote(proxy: proxy)
    }

    /// Binds a delivery directly — the composition root's seam for anything
    /// that is not a bare proxy call (in Debug, the stand-in purse in DI.swift).
    static func bind(delivery: any VialGrantDelivering) {
        self.delivery = delivery
    }

    /// Binds the proxy-backed halves that have no stand-in: subscription
    /// proofs and the remote gate config. Called in both configurations —
    /// the Debug purse replaces only the vial delivery.
    static func bindRemote(proxy: ProxyClient) {
        attestor = ProxyPlusAttestor(proxy: proxy)
        configFetch = { try await proxy.gateConfig() }
    }

    static let purchases = StoreKitEntitlementStore(
        delivery: LazyVialDelivery(), attestor: LazyPlusAttestor()
    )
    static let usage = DailyUsageStore()
    static let gateConfig = GateConfigStore()
    static let page = PageEntitlements(
        entitlements: purchases,
        usage: usage,
        gateConfig: { await gateConfig.current }
    )

    /// Re-reads the server's knobs. Failure keeps the last known values —
    /// the gate never waits on the network and never loses its defaults.
    static func refreshGateConfig() async {
        guard let configFetch, let remote = try? await configFetch() else { return }
        await gateConfig.update(GateConfig(
            freeMomentsPerDay: remote.freeMomentsPerDay,
            plusImageDailySoftCap: remote.plusImageDailySoftCap,
            cooldownCurveSeconds: remote.cooldownCurveSeconds
        ))
    }

    /// Resolves the binding at call time, so the store can be a `let` while the
    /// proxy is composed later in `AppDI`.
    private struct LazyVialDelivery: VialGrantDelivering {
        func deliver(_ grant: VialGrant) async throws {
            guard let delivery = LiveCommerce.delivery else {
                throw CommerceError.deliveryPending
            }
            try await delivery.deliver(grant)
        }
    }

    /// Same call-time resolution for subscription proofs.
    private struct LazyPlusAttestor: PlusAttesting {
        func attest(_ proof: EntitlementProof) async throws {
            guard let attestor = LiveCommerce.attestor else { return }
            try await attestor.attest(proof)
        }
    }
}

/// The page's view of commerce: the snapshot the send gate reads and the
/// counter a completed exchange ticks. Both halves must come from the same
/// accounting, or the gate reads a count the exchange never records.
struct PageEntitlements: Sendable {
    let resolver: EntitlementResolver
    let usage: any DailyUsageAccounting
    /// The gate knobs as last fetched from the server; the compiled-in
    /// defaults until then, and always for harnesses.
    let gateConfig: @Sendable () async -> GateConfig

    init(
        entitlements: any EntitlementProviding,
        usage: any DailyUsageAccounting,
        gateConfig: @escaping @Sendable () async -> GateConfig = { GateConfig() }
    ) {
        self.resolver = EntitlementResolver(entitlements: entitlements, usage: usage)
        self.usage = usage
        self.gateConfig = gateConfig
    }

    func snapshot(at now: Date = Date()) async -> EntitlementSnapshot {
        await resolver.snapshot(at: now)
    }

    @discardableResult
    func record(_ modality: Modality, at now: Date = Date()) async -> DailyUsage {
        await usage.record(modality, at: now)
    }

    /// Free tier with a counter that dies with the process — for tests,
    /// previews and the dev harness, none of which may spend the user's real
    /// daily cap.
    static func ephemeral(seed: DailyUsage? = nil) -> PageEntitlements {
        PageEntitlements(
            entitlements: FailClosedEntitlementProvider(),
            usage: DailyUsageStore(storage: EphemeralDailyUsageStorage(seed: seed))
        )
    }
}
