import Foundation
import InkCore
import InkMoney

/// Where the daily counters rest between launches. InkMoney owns the roll
/// math (`DailyUsageLedger`) and deliberately knows nothing about storage;
/// this is the App layer's half of that seam.
protocol DailyUsageStorage: Sendable {
    func load() -> DailyUsage?
    func save(_ usage: DailyUsage)
}

/// `UserDefaults` is documented thread-safe but Foundation marks its
/// `Sendable` conformance unavailable, so the guarantee is carried here
/// explicitly rather than hopping every counter write to the main actor.
struct UserDefaultsDailyUsageStorage: DailyUsageStorage, @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = "ink.dailyUsage") {
        self.defaults = defaults
        self.key = key
    }

    func load() -> DailyUsage? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(DailyUsage.self, from: data)
    }

    func save(_ usage: DailyUsage) {
        guard let data = try? JSONEncoder().encode(usage) else { return }
        defaults.set(data, forKey: key)
    }
}

/// Process-lifetime storage for tests, previews and harnesses — a counter that
/// must not outlive the run and must never touch the user's preferences.
final class EphemeralDailyUsageStorage: DailyUsageStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: DailyUsage?

    init(seed: DailyUsage? = nil) { stored = seed }

    func load() -> DailyUsage? {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    func save(_ usage: DailyUsage) {
        lock.lock()
        defer { lock.unlock() }
        stored = usage
    }
}

/// Durable daily-cap accounting. The counter this replaces lived on
/// `PageInteractor`, which SwiftUI rebuilds on every Book switch and every
/// shelf→page round trip — so a free user beat the 5-moments/day cap simply by
/// backing out and coming back, and the paywall itself triggered the reset.
/// Here it survives page re-entry, Book switching and cold launch.
///
/// The proxy stays authoritative: `reconcile(with:)` folds a server count in
/// (upward only) the day the client gains a usage endpoint.
actor DailyUsageStore: DailyUsageAccounting {
    private var ledger: DailyUsageLedger
    private let storage: any DailyUsageStorage

    init(storage: any DailyUsageStorage = UserDefaultsDailyUsageStorage(), calendar: Calendar = .current) {
        self.storage = storage
        if let restored = storage.load() {
            ledger = DailyUsageLedger(usage: restored, calendar: calendar)
        } else {
            ledger = DailyUsageLedger(calendar: calendar)
        }
    }

    func currentUsage(at now: Date = Date()) -> DailyUsage {
        let before = ledger.usage
        let usage = ledger.current(at: now)
        // Only a real day roll changes anything; reading the counters must not
        // write a preference on every send gate.
        if usage != before { storage.save(usage) }
        return usage
    }

    @discardableResult
    func record(_ modality: Modality, at now: Date = Date()) -> DailyUsage {
        let usage = ledger.record(modality, at: now)
        storage.save(usage)
        return usage
    }

    /// Folds a server-reported count in. Unused until the client gains a usage
    /// endpoint (`GET /v1/credits` carries the wallet, not the day) — kept
    /// bound so the authoritative path is one call away.
    @discardableResult
    func reconcile(with server: DailyUsage, at now: Date = Date()) -> DailyUsage {
        let usage = ledger.reconcile(with: server, at: now)
        storage.save(usage)
        return usage
    }
}
