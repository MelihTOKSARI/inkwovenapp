import Foundation
import Testing
@testable import InkMoney

@Suite("CreditLedger (tasks G4/C5)")
struct CreditLedgerTests {
    @Test("buy → reserve → settle spends exactly once")
    func happyPathSpend() throws {
        var ledger = CreditLedger()
        try ledger.credit(10, reason: .purchase)
        let reservation = try ledger.reserve(1)
        #expect(ledger.available == 9)
        #expect(ledger.balance == 10, "a hold is not yet a spend")

        let settled = ledger.settle(reservation.id)
        #expect(settled)
        #expect(ledger.balance == 9)
        #expect(ledger.available == 9)
    }

    @Test("refund-on-failure: release restores the full balance")
    func releaseRefunds() throws {
        var ledger = CreditLedger()
        try ledger.credit(1, reason: .onboardingGrant)
        let reservation = try ledger.reserve(1)
        #expect(ledger.available == 0)

        let released = ledger.release(reservation.id)
        #expect(released)
        #expect(ledger.available == 1)
        #expect(ledger.balance == 1)
    }

    @Test("reserve beyond available throws — no negative balances, ever")
    func insufficientCreditsThrows() throws {
        var ledger = CreditLedger()
        try ledger.credit(1, reason: .onboardingGrant)
        _ = try ledger.reserve(1)
        #expect(throws: CreditError.insufficientCredits(available: 0, requested: 1)) {
            try ledger.reserve(1)
        }
    }

    @Test("settle is idempotent — double settle spends once")
    func settleIdempotent() throws {
        var ledger = CreditLedger()
        try ledger.credit(5, reason: .purchase)
        let r = try ledger.reserve(1)
        let first = ledger.settle(r.id)
        let second = ledger.settle(r.id)
        #expect(first)
        #expect(!second)
        #expect(ledger.balance == 4)
        #expect(ledger.entries.count == 2)
    }

    @Test("release is idempotent, and settle-after-release is a no-op")
    func releaseIdempotentAndExclusive() throws {
        var ledger = CreditLedger()
        try ledger.credit(5, reason: .purchase)
        let r = try ledger.reserve(1)
        let firstRelease = ledger.release(r.id)
        let secondRelease = ledger.release(r.id)
        let settleAfterRelease = ledger.settle(r.id)
        #expect(firstRelease)
        #expect(!secondRelease)
        #expect(!settleAfterRelease, "a released reservation can never be spent")
        #expect(ledger.balance == 5)
    }

    @Test("re-reserving an active id returns the same hold without double-holding")
    func reserveIdempotentByID() throws {
        var ledger = CreditLedger()
        try ledger.credit(5, reason: .purchase)
        let id = UUID()
        let first = try ledger.reserve(1, id: id)
        let second = try ledger.reserve(1, id: id)
        #expect(first == second)
        #expect(ledger.heldAmount == 1)
    }

    @Test("a hostile server amount is a typed error, not a crash — and mints nothing")
    func invalidAmountsThrow() throws {
        var ledger = CreditLedger()
        // The exploit that worked against the proxy's ledger: a negative
        // amount reserving into a negative hold, which inflates `available`.
        #expect(throws: CreditError.invalidAmount(-100)) { try ledger.reserve(-100) }
        #expect(throws: CreditError.invalidAmount(0)) { try ledger.reserve(0) }
        #expect(throws: CreditError.invalidAmount(-1)) { try ledger.credit(-1, reason: .purchase) }
        #expect(throws: CreditError.invalidAmount(0)) { try ledger.credit(0, reason: .purchase) }
        #expect(throws: CreditError.invalidAmount(CreditLedger.maxTransactionAmount + 1)) {
            try ledger.credit(CreditLedger.maxTransactionAmount + 1, reason: .purchase)
        }
        #expect(ledger.balance == 0)
        #expect(ledger.available == 0)
        #expect(ledger.heldAmount == 0)
    }

    @Test("failureRefund reverses a settled spend exactly once")
    func settledSpendCanBeRefunded() throws {
        var ledger = CreditLedger()
        try ledger.credit(3, reason: .purchase)
        let r = try ledger.reserve(1)
        let settled = ledger.settle(r.id)
        #expect(settled)
        #expect(ledger.balance == 2)

        let refunded = try ledger.refund(r.id)
        #expect(refunded == 1)
        #expect(ledger.balance == 3, "the clip never arrived — the vial returns")
        #expect(ledger.entries.last?.reason == .failureRefund)

        #expect(throws: CreditError.reservationNotSettled(r.id)) { try ledger.refund(r.id) }
        #expect(ledger.balance == 3, "a replayed refund never credits twice")
    }

    @Test("refunding something that never settled throws rather than minting credit")
    func refundRequiresSettlement() throws {
        var ledger = CreditLedger()
        try ledger.credit(2, reason: .purchase)
        let held = try ledger.reserve(1)
        #expect(throws: CreditError.reservationNotSettled(held.id)) { try ledger.refund(held.id) }

        let released = try ledger.reserve(1, id: UUID())
        _ = ledger.release(released.id)
        #expect(throws: CreditError.reservationNotSettled(released.id)) { try ledger.refund(released.id) }

        let unknown = UUID()
        #expect(throws: CreditError.reservationNotSettled(unknown)) { try ledger.refund(unknown) }
        #expect(ledger.balance == 2)
    }

    @Test("property: random op sequences never go negative and never double-resolve")
    func propertyInvariants() throws {
        var generator = SplitMix64(seed: 0xC0FFEE)
        for _ in 0..<200 {
            var ledger = CreditLedger()
            var openReservations: [CreditReservation] = []
            for _ in 0..<60 {
                switch generator.next() % 5 {
                case 0:
                    try ledger.credit(Int(generator.next() % 3) + 1, reason: .purchase)
                case 1:
                    if let r = try? ledger.reserve(1) { openReservations.append(r) }
                case 2:
                    if let r = openReservations.randomElement(using: &generator) { ledger.settle(r.id) }
                case 3:
                    if let r = openReservations.randomElement(using: &generator) { ledger.release(r.id) }
                default:
                    // Replay a resolve on a random past reservation (idempotency probe).
                    if let r = openReservations.first { ledger.settle(r.id); ledger.release(r.id) }
                }
                #expect(ledger.available >= 0)
                #expect(ledger.balance >= 0)
                #expect(ledger.heldAmount >= 0)
            }
        }
    }
}

/// Deterministic RNG so property failures reproduce.
private struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
