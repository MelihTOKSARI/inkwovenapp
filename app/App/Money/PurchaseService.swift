import Foundation
import StoreKit
import InkMoney
import InkNet

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
    /// StoreKit took the payment but the server-side wallet has not credited
    /// it yet. The transaction stays UNFINISHED, so StoreKit redelivers it on
    /// the next launch and the vials arrive then — nobody pays for nothing.
    case deliveryPending
    /// The server refused the receipt TERMINALLY (revoked, already redeemed
    /// by another identity, invalid). The transaction is finished so it can
    /// never loop (audit M-4); the wallet was not credited.
    case deliveryRejected
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
    /// Whether the introductory offer (the weekly trial) is open to THIS
    /// Apple ID. Nil while unknown. The paywall shows trial claims only on
    /// `true` — a returning subscriber shown "free for 3 days" is charged
    /// immediately, which is a 3.1.2 rejection and a broken promise (C-2).
    func isEligibleForIntroOffer(_ productID: String) async -> Bool?
    /// Fires after a verified vial purchase has been credited server-side, so
    /// the shop can re-read the wallet. Carries no amount: the balance comes
    /// from the proxy, never from adding up what the client thinks it bought.
    func creditGrants() -> AsyncStream<Void>
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
    private var grantObservers: [UUID: AsyncStream<Void>.Continuation] = [:]

    /// Where a verified vial purchase goes. Nil until the composition root
    /// binds it — and a nil delivery never finishes a consumable transaction,
    /// so the purchase waits for the next launch rather than evaporating.
    private let delivery: (any VialGrantDelivering)?
    /// Where a verified subscription receipt goes so the server-side daily
    /// quota meters this identity as Plus (audit M-2). Best-effort: a failure
    /// changes nothing here — the next refresh re-proves.
    private let attestor: (any PlusAttesting)?

    private static let subscriptions: Set<String> = [ProductID.plusWeekly, ProductID.plusMonthly]

    init(delivery: (any VialGrantDelivering)? = nil, attestor: (any PlusAttesting)? = nil) {
        self.delivery = delivery
        self.attestor = attestor
    }

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

    nonisolated func creditGrants() -> AsyncStream<Void> {
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
        var proof: EntitlementProof?
        for await result in StoreKit.Transaction.currentEntitlements {
            // Fail closed: an unverified entitlement is no entitlement.
            guard case .verified(let transaction) = result else { continue }
            guard transaction.revocationDate == nil else { continue }
            if let expiry = transaction.expirationDate, expiry <= Date() { continue }
            if Self.subscriptions.contains(transaction.productID) {
                entitled = true
                // The same verified receipt, kept to prove Plus to the proxy —
                // the server re-verifies it, so this asserts nothing by itself.
                proof = EntitlementProof(
                    productID: transaction.productID,
                    transactionID: String(transaction.id),
                    jws: result.jwsRepresentation
                )
            }
        }
        setTier(entitled ? .plus : .free)
        // Fire-and-forget: the server-side quota widens when this lands and
        // self-heals on the next refresh when it doesn't. Nothing user-visible
        // waits on it.
        if let proof, let attestor {
            Task { try? await attestor.attest(proof) }
        }
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
            // The wallet is server-side, so the purchase is not done until the
            // proxy has credited it. A transient failure leaves the
            // transaction unfinished for redelivery; a TERMINAL refusal
            // finishes it so it can never loop (audit M-4) and reports
            // honestly rather than pretending vials arrived.
            switch await deliver(verification, transaction: transaction) {
            case .credited:
                await transaction.finish()
                await refresh()
                return .success
            case .terminal:
                await transaction.finish()
                await refresh()
                throw CommerceError.deliveryRejected
            case .retry:
                throw CommerceError.deliveryPending
            }
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

    func isEligibleForIntroOffer(_ productID: String) async -> Bool? {
        guard let product = try? await product(for: productID),
              let subscription = product.subscription else { return nil }
        return await subscription.isEligibleForIntroOffer
    }

    // MARK: - Internals

    /// What one delivery attempt concluded (audit M-4).
    private enum DeliveryOutcome {
        /// The server credited the wallet — finish and celebrate.
        case credited
        /// The server refused TERMINALLY (revoked receipt, redeemed by
        /// another identity, invalid) — finish WITHOUT crediting, or
        /// StoreKit re-presents the same doomed transaction on every
        /// launch, forever.
        case terminal
        /// Transient (offline, 5xx, rate limit) — stay unfinished so
        /// StoreKit redelivers and the vials arrive when the road clears.
        case retry
    }

    private func apply(_ result: VerificationResult<StoreKit.Transaction>) async {
        guard case .verified(let transaction) = result else { return }
        // A refunded or revoked transaction buys nothing and must be
        // FINISHED (audit M-4): re-submitting it earns 400 revoked_receipt
        // every launch forever, and the queue never drains.
        if transaction.revocationDate != nil {
            await transaction.finish()
            await refresh()
            return
        }
        // A consumable that nobody took delivery of must stay unfinished:
        // StoreKit redelivers an unfinished transaction on the next launch,
        // but a finished one is gone for good. This is the path that redeems a
        // purchase whose delivery failed the first time.
        switch await deliver(result, transaction: transaction) {
        case .credited, .terminal:
            await transaction.finish()
        case .retry:
            break
        }
        await refresh()
    }

    /// Sends a verified consumable to the server-side wallet.
    ///
    /// Idempotency is the server's: the transaction id is the key, so a
    /// redelivered purchase credits exactly once no matter how many times this
    /// runs. Non-consumables pass straight through — there is nothing to credit.
    private func deliver(
        _ result: VerificationResult<StoreKit.Transaction>,
        transaction: StoreKit.Transaction
    ) async -> DeliveryOutcome {
        guard ProductID.consumables.contains(transaction.productID) else { return .credited }
        guard let delivery else { return .retry }
        do {
            try await delivery.deliver(VialGrant(
                productID: transaction.productID,
                transactionID: String(transaction.id),
                jws: result.jwsRepresentation
            ))
            for continuation in grantObservers.values { continuation.yield(()) }
            return .credited
        } catch let error as ProxyError {
            return Self.outcome(for: error)
        } catch {
            return .retry
        }
    }

    /// 4xx application answers are TERMINAL — retrying an invalid, revoked,
    /// or already-redeemed receipt can never succeed (audit M-4/T1). A rate
    /// limit is 4xx on the wire and transient in nature, so it retries; so
    /// does everything 5xx, offline, or transport-shaped.
    private static func outcome(for error: ProxyError) -> DeliveryOutcome {
        switch error {
        case .server(let status) where (400..<500).contains(status):
            return .terminal
        case .moderated, .paymentRequired:
            // 422/402 are 4xx too — the grant route never answers them
            // semantically, but if one arrives it is equally unretryable.
            return .terminal
        case .rateLimited, .offline, .transport, .server, .badResponse, .cancelled:
            return .retry
        }
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

    private func addGrantObserver(_ id: UUID, _ continuation: AsyncStream<Void>.Continuation) {
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
    /// Unknown — the paywall shows no trial claim it cannot back.
    func isEligibleForIntroOffer(_ productID: String) async -> Bool? { nil }
    func creditGrants() -> AsyncStream<Void> {
        AsyncStream { $0.finish() }
    }
}
