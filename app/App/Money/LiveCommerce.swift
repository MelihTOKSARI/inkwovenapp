import Foundation
import InkCore
import InkMoney

/// The one live commerce composition.
///
/// These bindings belong in `App/DI.swift` — the composition root — and moving
/// them there is a four-line change (see the handoff note). Until then they
/// live here as a single shared instance, because the alternative is worse:
/// `AppModel.bound` and the page's send gate reading two different receipts and
/// two different counters.
enum LiveCommerce {
    static let purchases = StoreKitEntitlementStore()
    static let usage = DailyUsageStore()
    static let page = PageEntitlements(entitlements: purchases, usage: usage)
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
