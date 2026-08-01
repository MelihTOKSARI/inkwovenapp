import Foundation
import Testing
import InkCore
@testable import InkMoney

@Suite("DailyUsageLedger — the free cap has to survive leaving the page")
struct DailyUsageLedgerTests {
    /// UTC so the day boundary is unambiguous wherever the tests run.
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        return c
    }

    private func date(_ iso: String) throws -> Date {
        let f = ISO8601DateFormatter()
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return try #require(f.date(from: iso))
    }

    @Test("counts accumulate within a day and are not reset by re-reading")
    func accumulatesWithinDay() throws {
        let morning = try date("2026-07-20T09:00:00Z")
        var ledger = DailyUsageLedger(now: morning, calendar: calendar)

        ledger.record(.ink, at: morning)
        ledger.record(.ink, at: try date("2026-07-20T11:00:00Z"))
        ledger.record(.image, at: try date("2026-07-20T23:59:59Z"))

        let usage = ledger.current(at: try date("2026-07-20T23:59:59Z"))
        #expect(usage.momentsUsed == 3, "re-entering the page must not zero the counter")
        #expect(usage.imagesUsed == 1)
    }

    @Test("the counter rolls at the calendar day boundary")
    func rollsAtMidnight() throws {
        var ledger = DailyUsageLedger(now: try date("2026-07-20T23:00:00Z"), calendar: calendar)
        ledger.record(.ink, at: try date("2026-07-20T23:00:00Z"))
        ledger.record(.ink, at: try date("2026-07-20T23:30:00Z"))
        #expect(ledger.current(at: try date("2026-07-20T23:30:00Z")).momentsUsed == 2)

        let next = ledger.current(at: try date("2026-07-21T00:00:01Z"))
        #expect(next.momentsUsed == 0)
        #expect(next.imagesUsed == 0)
    }

    @Test("winding the clock backwards never returns spent capacity")
    func backwardsClockGrantsNothing() throws {
        let today = try date("2026-07-20T12:00:00Z")
        var ledger = DailyUsageLedger(now: today, calendar: calendar)
        for _ in 0..<5 { ledger.record(.ink, at: today) }

        let rewound = ledger.current(at: try date("2026-07-14T12:00:00Z"))
        #expect(rewound.momentsUsed == 5, "the client clock must never grant capacity")
        #expect(rewound.dayStart == calendar.startOfDay(for: today))
    }

    @Test("only images tick the image counter; every modality is a moment")
    func modalityAccounting() throws {
        let now = try date("2026-07-20T12:00:00Z")
        var ledger = DailyUsageLedger(now: now, calendar: calendar)
        ledger.record(.ink, at: now)
        ledger.record(.video, at: now)
        ledger.record(.image, at: now)
        #expect(ledger.usage.momentsUsed == 3)
        #expect(ledger.usage.imagesUsed == 1)
    }

    @Test("reconcile takes the higher count — a stale server reply hands nothing back")
    func reconcileNeverLowers() throws {
        let now = try date("2026-07-20T12:00:00Z")
        var ledger = DailyUsageLedger(now: now, calendar: calendar)
        for _ in 0..<4 { ledger.record(.ink, at: now) }

        let stale = DailyUsage(dayStart: calendar.startOfDay(for: now), momentsUsed: 1)
        #expect(ledger.reconcile(with: stale, at: now).momentsUsed == 4)

        let authoritative = DailyUsage(dayStart: calendar.startOfDay(for: now), momentsUsed: 9, imagesUsed: 2)
        let merged = ledger.reconcile(with: authoritative, at: now)
        #expect(merged.momentsUsed == 9, "the proxy may raise the count")
        #expect(merged.imagesUsed == 2)
    }

    @Test("a server count for a different day is ignored")
    func reconcileIgnoresOtherDays() throws {
        let now = try date("2026-07-20T12:00:00Z")
        var ledger = DailyUsageLedger(now: now, calendar: calendar)
        ledger.record(.ink, at: now)

        let yesterday = DailyUsage(dayStart: calendar.startOfDay(for: try date("2026-07-19T12:00:00Z")),
                                   momentsUsed: 99)
        #expect(ledger.reconcile(with: yesterday, at: now).momentsUsed == 1)
    }

    @Test("negative persisted counters clamp instead of granting capacity")
    func negativeCountersClamp() throws {
        let now = try date("2026-07-20T12:00:00Z")
        let poisoned = DailyUsage(dayStart: calendar.startOfDay(for: now), momentsUsed: -50, imagesUsed: -3)
        #expect(poisoned.momentsUsed == 0)
        #expect(poisoned.imagesUsed == 0)
    }

    @Test("the ledger round-trips through Codable, so it can be persisted as-is")
    func codableRoundtrip() throws {
        let now = try date("2026-07-20T12:00:00Z")
        var ledger = DailyUsageLedger(now: now, calendar: calendar)
        ledger.record(.image, at: now)

        let decoded = try JSONDecoder().decode(DailyUsage.self, from: JSONEncoder().encode(ledger.usage))
        var restored = DailyUsageLedger(usage: decoded, calendar: calendar)
        #expect(restored.current(at: now) == ledger.usage, "a cold launch resumes the same day's count")
    }
}

@Suite("EntitlementResolver + fail-closed default")
struct EntitlementResolverTests {
    private struct StubUsage: DailyUsageAccounting {
        let usage: DailyUsage
        func currentUsage(at now: Date) async -> DailyUsage { usage }
        func record(_ modality: Modality, at now: Date) async -> DailyUsage { usage }
    }

    private struct PlusProvider: EntitlementProviding {
        func currentSnapshot() async -> EntitlementSnapshot {
            EntitlementSnapshot(tier: .plus, memoryEnabled: true)
        }
        func snapshots() -> AsyncStream<EntitlementSnapshot> {
            AsyncStream { $0.finish() }
        }
    }

    @Test("an unbound purchase adapter grants nothing")
    func failClosedDefaultGrantsNothing() async {
        let snapshot = await FailClosedEntitlementProvider().currentSnapshot()
        #expect(snapshot.tier == .free)
        #expect(!snapshot.memoryEnabled)
        #expect(snapshot.archiveWindowDays == 30)
        #expect(SendGate.canUseMemory(snapshot: snapshot) == .paywall(.memory))
    }

    @Test("the resolver joins durable counters to the entitlement tier")
    func resolverComposesBothHalves() async {
        let usage = DailyUsage(dayStart: Date(), momentsUsed: 7, imagesUsed: 21)
        let resolver = EntitlementResolver(entitlements: PlusProvider(), usage: StubUsage(usage: usage))
        let snapshot = await resolver.snapshot()

        #expect(snapshot.tier == .plus)
        #expect(snapshot.momentsUsedToday == 7)
        #expect(snapshot.imagesUsedToday == 21)
        #expect(snapshot.memoryEnabled)
        // The Plus image soft-cap branch is only reachable once real counters
        // arrive — with a hardcoded snapshot it was dead code.
        #expect(SendGate.canSend(modality: .image, snapshot: snapshot) == .cooldown(seconds: 300))
    }

    @Test("a fail-closed provider still paywalls the 6th moment of the day")
    func failClosedResolverGatesAtTheCap() async {
        let usage = DailyUsage(dayStart: Date(), momentsUsed: 5)
        let resolver = EntitlementResolver(
            entitlements: FailClosedEntitlementProvider(),
            usage: StubUsage(usage: usage)
        )
        let snapshot = await resolver.snapshot()
        #expect(SendGate.canSend(modality: .ink, snapshot: snapshot) == .paywall(.moments))
    }
}
