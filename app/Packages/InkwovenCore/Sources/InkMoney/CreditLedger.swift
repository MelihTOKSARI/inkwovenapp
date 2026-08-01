import Foundation

public enum CreditReason: String, Codable, Sendable {
    case purchase
    case onboardingGrant
    case videoSpend
    case failureRefund
}

public struct LedgerEntry: Equatable, Sendable, Codable {
    public var id: UUID
    public var delta: Int
    public var reason: CreditReason
    public var at: Date

    public init(id: UUID = UUID(), delta: Int, reason: CreditReason, at: Date) {
        self.id = id
        self.delta = delta
        self.reason = reason
        self.at = at
    }
}

public struct CreditReservation: Equatable, Sendable, Codable {
    public var id: UUID
    public var amount: Int

    public init(id: UUID = UUID(), amount: Int) {
        self.id = id
        self.amount = amount
    }
}

public enum CreditError: Error, Equatable {
    case insufficientCredits(available: Int, requested: Int)
    case reservationAlreadyResolved(UUID)
    /// Amounts arrive from the proxy (pack grants, video job costs). A
    /// non-positive or absurd amount is a typed error, never a trap: the
    /// server sending `amount: 0` or `amount: -100` must not crash the app,
    /// and must never mint credits.
    case invalidAmount(Int)
    /// Refund applies only to a reservation that actually settled.
    case reservationNotSettled(UUID)
}

/// Pure credit math (tasks G1/G4). Flow: `reserve(1)` before a video job,
/// `settle` when the clip develops, `release` on any failure (refund path).
/// Invariants, property-tested: available never negative, settle/release
/// idempotent, a reservation resolves exactly once.
public struct CreditLedger: Equatable, Sendable {
    private enum Resolution: Equatable, Sendable { case settled(Int), released, refunded }

    public private(set) var entries: [LedgerEntry] = []
    private var activeHolds: [UUID: Int] = [:]
    private var resolutions: [UUID: Resolution] = [:]

    /// Upper bound on any single credit or reservation. Keeps a hostile or
    /// buggy server amount from overflowing the `balance` sum; far above any
    /// real pack (the largest is 100).
    public static let maxTransactionAmount = 100_000

    public init() {}

    public var balance: Int { entries.reduce(0) { $0 + $1.delta } }
    public var heldAmount: Int { activeHolds.values.reduce(0, +) }
    public var available: Int { balance - heldAmount }

    private static func validate(_ amount: Int) throws {
        guard amount > 0, amount <= maxTransactionAmount else {
            throw CreditError.invalidAmount(amount)
        }
    }

    public mutating func credit(_ amount: Int, reason: CreditReason, at date: Date = Date()) throws {
        try Self.validate(amount)
        entries.append(LedgerEntry(delta: amount, reason: reason, at: date))
    }

    /// Idempotent by reservation id: re-reserving an active id returns the
    /// same reservation without holding twice.
    public mutating func reserve(_ amount: Int = 1, id: UUID = UUID()) throws -> CreditReservation {
        try Self.validate(amount)
        if let held = activeHolds[id] {
            return CreditReservation(id: id, amount: held)
        }
        if resolutions[id] != nil {
            throw CreditError.reservationAlreadyResolved(id)
        }
        guard available >= amount else {
            throw CreditError.insufficientCredits(available: available, requested: amount)
        }
        activeHolds[id] = amount
        return CreditReservation(id: id, amount: amount)
    }

    /// Converts the hold into a spend. Returns false (and changes nothing) if
    /// the reservation is unknown or already resolved.
    @discardableResult
    public mutating func settle(_ id: UUID, at date: Date = Date()) -> Bool {
        guard let amount = activeHolds.removeValue(forKey: id) else { return false }
        resolutions[id] = .settled(amount)
        entries.append(LedgerEntry(delta: -amount, reason: .videoSpend, at: date))
        return true
    }

    /// Drops the hold without spending — the refund-on-failure path taken
    /// while the job is still in flight (download failed, crisis preempted the
    /// exchange). Returns false (and changes nothing) if unknown or already
    /// resolved.
    @discardableResult
    public mutating func release(_ id: UUID) -> Bool {
        guard activeHolds.removeValue(forKey: id) != nil else { return false }
        resolutions[id] = .released
        return true
    }

    /// Refunds a reservation that already SETTLED — the clip was billed and
    /// then failed to arrive, or the proxy reversed the spend. Unlike
    /// `release` (which only drops a hold) this posts a compensating
    /// `.failureRefund` entry, so the wallet history shows the charge and its
    /// reversal. Idempotent: a second refund of the same reservation throws
    /// rather than crediting twice.
    @discardableResult
    public mutating func refund(_ id: UUID, at date: Date = Date()) throws -> Int {
        guard case .settled(let amount)? = resolutions[id] else {
            throw CreditError.reservationNotSettled(id)
        }
        resolutions[id] = .refunded
        entries.append(LedgerEntry(delta: amount, reason: .failureRefund, at: date))
        return amount
    }
}
