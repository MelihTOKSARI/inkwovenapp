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

    static func bind(proxy: ProxyClient) {
        delivery = ProxyVialDelivery(proxy: proxy)
    }

    static let purchases = StoreKitEntitlementStore(delivery: LazyVialDelivery())
    static let usage = DailyUsageStore()
    static let page = PageEntitlements(entitlements: purchases, usage: usage)

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
}

/// The page's view of commerce: the snapshot the send gate reads and the
/// counter a completed exchange ticks. Both halves must come from the same
/// accounting, or the gate reads a count the exchange never records.
struct PageEntitlements: Sendable {
    let resolver: EntitlementResolver
    let usage: any DailyUsageAccounting

    init(entitlements: any EntitlementProviding, usage: any DailyUsageAccounting) {
        self.resolver = EntitlementResolver(entitlements: entitlements, usage: usage)
        self.usage = usage
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
