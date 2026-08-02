import Foundation
import StoreKit
import InkMoney

/// What a purchase attempt did. `pending` is its own case on purpose: an
/// Ask-to-Buy or SCA transaction exists but nothing is entitled yet, and
/// treating it as success is how a minor ends up with Plus their parent never
/// approved.
enum PurchaseOutcome: Equatable, Sendable {
    case success
    case pending
    case cancelled
}

enum CommerceError: Error, Equatable {
    /// No StoreKit product for the identifier — App Store Connect records are
    /// absent, or the device is offline. Grants nothing.
    case productUnavailable(String)
    /// The receipt did not verify. Never granted; never finished.
    case unverified
}

/// The App layer's purchase seam. It extends `EntitlementProviding` rather
/// than replacing it so the entitlement half stays the InkMoney protocol the
/// gate already reads — a RevenueCat adapter drops in here unchanged.
protocol PurchaseServicing: EntitlementProviding {
    /// Begins the `Transaction.updates` listener and reconciles entitlements.
    func start() async
    func refresh() async
    /// "Restore a binding" — App Review requires this to work.
    func restore() async throws
    func purchase(_ productID: String) async throws -> PurchaseOutcome
    /// Localized storefront price. Hardcoded USD literals are a misleading-price
    /// rejection in every non-USD storefront.
    func displayPrice(for productID: String) async -> String?
    /// Credit amounts granted by verified consumable purchases, in order.
    func creditGrants() -> AsyncStream<Int>
}

/// Verified-purchase entitlements, StoreKit 2 only.
///
/// `bound` used to be a persisted `UserDefaults` boolean that `confirmBind()`
/// set without charging anything: free Plus for every user, forgeable through
/// the argument domain, and impossible to revoke after a refund. Here the tier
/// is derived from `Transaction.currentEntitlements` at launch and kept live by
/// `Transaction.updates`, so refund, cancellation, expiry and family-sharing
/// revocation all take Plus away on the next tick. Nothing entitlement-shaped
/// is persisted client-side.
///
/// An unverified `VerificationResult` grants nothing and is not finished — the
/// only safe reading of a receipt we cannot trust.
///
/// RevenueCat stays deliberately unbound: this conforms to the same
/// `EntitlementProviding` seam, so swapping the adapter is a one-line change in
/// the composition root and no fabricated SDK ships in the meantime.
actor StoreKitEntitlementStore: PurchaseServicing {
    private var tier: Tier = .free
    private var products: [String: Product] = [:]
    private var updatesTask: Task<Void, Never>?

    private var entitlementObservers: [UUID: AsyncStream<EntitlementSnapshot>.Continuation] = [:]
    private var grantObservers: [UUID: AsyncStream<Int>.Continuation] = [:]

    private static let subscriptions: Set<String> = [ProductID.plusWeekly, ProductID.plusMonthly]

    init() {}

    deinit { updatesTask?.cancel() }

    // MARK: - EntitlementProviding

    func currentSnapshot() -> EntitlementSnapshot {
        // Usage counters are joined in by `EntitlementResolver`; this half
        // carries only what a receipt can prove.
        EntitlementSnapshot(tier: tier, memoryEnabled: tier == .plus)
    }

    nonisolated func snapshots() -> AsyncStream<EntitlementSnapshot> {
        AsyncStream { continuation in
            let id = UUID()
            continuation.onTermination = { _ in
                Task { await self.removeEntitlementObserver(id) }
            }
            Task { await self.addEntitlementObserver(id, continuation) }
        }
    }

    nonisolated func creditGrants() -> AsyncStream<Int> {
        AsyncStream { continuation in
            let id = UUID()
            continuation.onTermination = { _ in
                Task { await self.removeGrantObserver(id) }
            }
            Task { await self.addGrantObserver(id, continuation) }
        }
    }

    // MARK: - Lifecycle

    func start() async {
        guard updatesTask == nil else { return }
        // The listener is armed BEFORE the first reconcile so a transaction
        // that lands during launch is not dropped.
        updatesTask = Task { [weak self] in
            for await update in StoreKit.Transaction.updates {
                guard let self else { return }
                await self.apply(update)
            }
        }
        await refresh()
    }

    func refresh() async {
        var entitled = false
        for await result in StoreKit.Transaction.currentEntitlements {
            // Fail closed: an unverified entitlement is no entitlement.
            guard case .verified(let transaction) = result else { continue }
            guard transaction.revocationDate == nil else { continue }
            if let expiry = transaction.expirationDate, expiry <= Date() { continue }
            if Self.subscriptions.contains(transaction.productID) { entitled = true }
        }
        setTier(entitled ? .plus : .free)
    }

    func restore() async throws {
        try await AppStore.sync()
        await refresh()
    }

    // MARK: - Buying

    func purchase(_ productID: String) async throws -> PurchaseOutcome {
        guard let product = try await product(for: productID) else {
            throw CommerceError.productUnavailable(productID)
        }
        switch try await product.purchase() {
        case .success(let verification):
            guard case .verified(let transaction) = verification else {
                // Do not finish it: an unverified transaction stays in the
                // queue for StoreKit to re-present rather than being consumed
                // by a client that could not check it.
                throw CommerceError.unverified
            }
            grant(for: transaction.productID)
            await transaction.finish()
            await refresh()
            return .success
        case .pending:
            // Ask to Buy / SCA. Entitlement arrives (if ever) through
            // `Transaction.updates`, never from here.
            return .pending
        case .userCancelled:
            return .cancelled
        @unknown default:
            return .cancelled
        }
    }

    func displayPrice(for productID: String) async -> String? {
        (try? await product(for: productID))??.displayPrice
    }

    // MARK: - Internals

    private func apply(_ result: VerificationResult<StoreKit.Transaction>) async {
        guard case .verified(let transaction) = result else { return }
        // A consumable that nobody took delivery of must stay unfinished:
        // StoreKit redelivers an unfinished transaction on the next launch,
        // but a finished one is gone for good. `Transaction.updates` can fire
        // before the shell has attached its observer, so finishing here
        // unconditionally would take the user's money and drop the vials.
        if !grant(for: transaction.productID) {
            await refresh()
            return
        }
        await transaction.finish()
        await refresh()
    }

    /// Consumables are credited exactly once, at the moment a verified
    /// transaction arrives — never from a button tap. Returns false when the
    /// grant found no taker, leaving the transaction open for redelivery.
    @discardableResult
    private func grant(for productID: String) -> Bool {
        guard let amount = ProductID.creditAmount(for: productID) else {
            return true // not a consumable — nothing to deliver
        }
        guard !grantObservers.isEmpty else { return false }
        for continuation in grantObservers.values { continuation.yield(amount) }
        return true
    }

    private func product(for productID: String) async throws -> Product? {
        if let cached = products[productID] { return cached }
        let fetched = try await Product.products(for: [productID])
        for product in fetched { products[product.id] = product }
        return products[productID]
    }

    private func setTier(_ next: Tier) {
        guard next != tier else { return }
        tier = next
        let snapshot = currentSnapshot()
        for continuation in entitlementObservers.values { continuation.yield(snapshot) }
    }

    private func addEntitlementObserver(
        _ id: UUID, _ continuation: AsyncStream<EntitlementSnapshot>.Continuation
    ) {
        entitlementObservers[id] = continuation
        continuation.yield(currentSnapshot())
    }

    private func removeEntitlementObserver(_ id: UUID) {
        entitlementObservers.removeValue(forKey: id)
    }

    private func addGrantObserver(_ id: UUID, _ continuation: AsyncStream<Int>.Continuation) {
        grantObservers[id] = continuation
    }

    private func removeGrantObserver(_ id: UUID) {
        grantObservers.removeValue(forKey: id)
    }
}

/// Fail-closed purchase service for harnesses, previews and tests: nothing is
/// entitled, nothing can be bought, and no StoreKit call is made. Binding this
/// where a real adapter is missing degrades to least-entitled rather than to
/// whatever a client boolean happens to say.
struct UnboundPurchaseService: PurchaseServicing {
    private let entitlements = FailClosedEntitlementProvider()

    init() {}

    func currentSnapshot() async -> EntitlementSnapshot { await entitlements.currentSnapshot() }
    func snapshots() -> AsyncStream<EntitlementSnapshot> { entitlements.snapshots() }

    func start() async {}
    func refresh() async {}
    func restore() async throws {}
    func purchase(_ productID: String) async throws -> PurchaseOutcome {
        throw CommerceError.productUnavailable(productID)
    }
    func displayPrice(for productID: String) async -> String? { nil }
    func creditGrants() -> AsyncStream<Int> {
        AsyncStream { $0.finish() }
    }
}
