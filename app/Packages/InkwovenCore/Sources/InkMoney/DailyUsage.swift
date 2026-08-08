import Foundation
import InkCore

/// One day's usage counters. The free-tier cap is meaningless unless this
/// survives page re-entry, Book switching, and cold launch — an in-memory
/// counter on a view model resets on all three, which hands a free user an
/// unlimited daily allowance.
public struct DailyUsage: Equatable, Sendable, Codable {
    /// Start of the day these counters belong to, in the user's calendar.
    public var dayStart: Date
    public var momentsUsed: Int
    public var imagesUsed: Int

    public init(dayStart: Date, momentsUsed: Int = 0, imagesUsed: Int = 0) {
        self.dayStart = dayStart
        self.momentsUsed = max(0, momentsUsed)
        self.imagesUsed = max(0, imagesUsed)
    }
}

/// The pure roll math behind `DailyUsageAccounting`. The App layer owns
/// persistence; this owns the only thing that can be got subtly wrong.
///
/// The client clock never GRANTS capacity: rolling forward is allowed (a real
/// new day), rolling backward is not. Winding the device clock back therefore
/// cannot reset a spent cap. The proxy stays authoritative — `reconcile`
/// exists so a server count can raise (never lower) the local one.
/// `DailyUsage` is the Codable part; the ledger itself deliberately is not, so
/// a persisted snapshot can never pin a stale calendar or time zone.
public struct DailyUsageLedger: Equatable, Sendable {
    public private(set) var usage: DailyUsage
    private let calendar: Calendar

    public init(now: Date = Date(), calendar: Calendar = .current) {
        self.calendar = calendar
        self.usage = DailyUsage(dayStart: calendar.startOfDay(for: now))
    }

    public init(usage: DailyUsage, calendar: Calendar = .current) {
        self.calendar = calendar
        self.usage = usage
    }

    /// Counters as of `now`, rolling to a fresh day when the calendar day has
    /// advanced. A `now` that predates the stored day is ignored — see the
    /// type's note on clock direction.
    public mutating func current(at now: Date = Date()) -> DailyUsage {
        let day = calendar.startOfDay(for: now)
        if day > usage.dayStart {
            usage = DailyUsage(dayStart: day)
        }
        return usage
    }

    /// Records one consumed moment and returns the counters after the roll.
    /// Ink counts as a moment; an image counts as a moment AND ticks the image
    /// counter that drives the Plus soft-cap cooldown. Moving pictures never
    /// pass through here — video is vial-gated, spent from the server-side
    /// wallet, and costs no daily moment.
    @discardableResult
    public mutating func record(_ modality: Modality, at now: Date = Date()) -> DailyUsage {
        var rolled = current(at: now)
        rolled.momentsUsed += 1
        if modality == .image { rolled.imagesUsed += 1 }
        usage = rolled
        return usage
    }

    /// Folds a server-reported count into the local one for the same day. Takes
    /// the maximum in both directions: the proxy is authoritative, but a stale
    /// or lower server response must never hand back capacity the user has
    /// already spent on this device.
    @discardableResult
    public mutating func reconcile(with server: DailyUsage, at now: Date = Date()) -> DailyUsage {
        let local = current(at: now)
        guard calendar.isDate(server.dayStart, inSameDayAs: local.dayStart) else { return local }
        usage = DailyUsage(
            dayStart: local.dayStart,
            momentsUsed: max(local.momentsUsed, server.momentsUsed),
            imagesUsed: max(local.imagesUsed, server.imagesUsed)
        )
        return usage
    }
}

/// Durable daily-cap accounting. The App layer binds a persistence-backed
/// implementation in DI (UserDefaults/file/SwiftData — InkMoney does not care
/// and must not know); InkMoney supplies only `DailyUsageLedger`, the rolling
/// math the implementation should wrap.
public protocol DailyUsageAccounting: Sendable {
    func currentUsage(at now: Date) async -> DailyUsage
    @discardableResult
    func record(_ modality: Modality, at now: Date) async -> DailyUsage
}

/// Composes the two halves of an `EntitlementSnapshot`: tier and memory from
/// the entitlement store, usage counters from durable accounting. This is the
/// surface the page's send gate should read — it is what makes `tier: .free`
/// and an in-memory moment counter unnecessary at the call site.
public struct EntitlementResolver: Sendable {
    private let entitlements: any EntitlementProviding
    private let usage: any DailyUsageAccounting

    public init(entitlements: any EntitlementProviding, usage: any DailyUsageAccounting) {
        self.entitlements = entitlements
        self.usage = usage
    }

    public func snapshot(at now: Date = Date()) async -> EntitlementSnapshot {
        let entitled = await entitlements.currentSnapshot()
        let counters = await usage.currentUsage(at: now)
        return EntitlementSnapshot(
            tier: entitled.tier,
            momentsUsedToday: counters.momentsUsed,
            imagesUsedToday: counters.imagesUsed,
            memoryEnabled: entitled.memoryEnabled
        )
    }
}

/// Fail-closed `EntitlementProviding` default. Binding this grants nothing:
/// free tier, memory off, archive window enforced. It exists so a composition
/// root with no purchase adapter yet — or one whose adapter failed to
/// initialize — degrades to the least-entitled state rather than to whatever
/// a persisted client-side boolean happens to say.
public struct FailClosedEntitlementProvider: EntitlementProviding {
    public init() {}

    public func currentSnapshot() async -> EntitlementSnapshot {
        EntitlementSnapshot(tier: .free, memoryEnabled: false)
    }

    /// One snapshot, then the stream ends — there is nothing to observe.
    public func snapshots() -> AsyncStream<EntitlementSnapshot> {
        AsyncStream { continuation in
            continuation.yield(EntitlementSnapshot(tier: .free, memoryEnabled: false))
            continuation.finish()
        }
    }
}
