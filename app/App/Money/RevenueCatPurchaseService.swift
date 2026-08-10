import Foundation
import RevenueCat
import StoreKit
import InkMoney
import InkNet

/// The RevenueCat half of commerce.
///
/// This conforms to the same `PurchaseServicing` seam as `StoreKitEntitlementStore`,
/// so which one the app runs is a single line in `LiveCommerce` and nothing
/// downstream — not `AppModel`, not the paywall, not the send gate — can tell the
/// difference. That was the point of declaring the protocol before the SDK existed.
///
/// **What RevenueCat owns here:** the subscription purchase, the entitlement, and
/// the Offering the paywall prices itself from. **What it does not own:** the vial
/// wallet. Credits buy real GPU seconds, the balance is the proxy's, and the proxy
/// verifies an Apple-signed receipt against Apple's own root before it credits
/// anything (`proxy/src/receipts.js`). RevenueCat records that purchase; it does not
/// get to authorise it.
///
/// **The one property this cannot preserve.** `StoreKitEntitlementStore` delivers a
/// consumable to the proxy BEFORE finishing the transaction, so a failed delivery
/// leaves the transaction unfinished and StoreKit redelivers it on the next launch —
/// nobody pays for nothing. Running purchases through RevenueCat means the SDK
/// finishes the transaction once *its* backend has recorded it, which is not the
/// same moment. The replacement is the `NON_RENEWING_PURCHASE` webhook landing on
/// the proxy (`revenuecat-plan.md` §3 step 5), idempotent on the same transaction id
/// the fast path below uses. **Until that route exists, `LiveCommerce.backend` must
/// stay `.storeKit`** — this type is complete but deliberately unbound.
actor RevenueCatPurchaseService: PurchaseServicing {

    /// The entitlement identifier configured in the RevenueCat dashboard
    /// (Product catalog → Entitlements). Both subscriptions attach to it; the
    /// vials attach to nothing, because a consumable grants credits, not Plus.
    static let plusEntitlement = "plus"

    private var tier: Tier = .free
    /// Packages by product identifier, from the current Offering. The paywall asks
    /// for prices by product id — it has never known what a Package is — so this is
    /// the whole of the translation between the room's vocabulary and RevenueCat's.
    private var packages: [String: Package] = [:]
    /// The Offering those packages came from, kept so a purchase can be attributed
    /// to it and so an experiment variant can be read off its metadata.
    private(set) var offering: Offering?
    /// Prices for ids no Offering carries — a product created in RevenueCat but not
    /// yet attached to a package. Keeps the shop from going blank on a misconfigured
    /// dashboard rather than punishing the user for it.
    private var looseProducts: [String: StoreProduct] = [:]

    private var listener: Task<Void, Never>?

    private var entitlementObservers: [UUID: AsyncStream<EntitlementSnapshot>.Continuation] = [:]
    private var grantObservers: [UUID: AsyncStream<Void>.Continuation] = [:]

    /// Where a verified vial purchase goes. Nil until the composition root binds it.
    private let delivery: (any VialGrantDelivering)?
    /// Where a verified subscription receipt goes, so the proxy's daily quota meters
    /// this identity as Plus (audit M-2). Best-effort; the next refresh re-proves.
    private let attestor: (any PlusAttesting)?

    init(delivery: (any VialGrantDelivering)? = nil, attestor: (any PlusAttesting)? = nil) {
        self.delivery = delivery
        self.attestor = attestor
    }

    deinit { listener?.cancel() }

    // MARK: - EntitlementProviding

    func currentSnapshot() -> EntitlementSnapshot {
        // Counters are joined in by `EntitlementResolver`; this half carries only
        // what a receipt can prove.
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
        guard listener == nil else { return }
        // Armed BEFORE the first read, so an entitlement that changes during launch
        // — a renewal, a restore on another device — is not missed.
        listener = Task { [weak self] in
            for await info in Purchases.shared.customerInfoStream {
                guard let self else { return }
                await self.apply(info)
            }
        }
        await refresh()
    }

    func refresh() async {
        if let info = try? await Purchases.shared.customerInfo() {
            setTier(info.entitlements.active[Self.plusEntitlement] != nil ? .plus : .free)
        }
        await refreshOfferings()
        await attestPlus()
    }

    /// Re-reads the current Offering. Failure keeps the last known packages — the
    /// paywall shows its last good prices rather than emptying itself, and
    /// `AppModel.storeFetchFailed` covers the cold case where there never were any.
    private func refreshOfferings() async {
        guard let offerings = try? await Purchases.shared.offerings(),
              let current = offerings.current else { return }
        offering = current
        packages = current.availablePackages.reduce(into: [:]) { map, package in
            map[package.storeProduct.productIdentifier] = package
        }
    }

    /// Carries the Apple-signed subscription receipt to the proxy.
    ///
    /// Read from StoreKit directly, not from RevenueCat: the proxy re-verifies the
    /// JWS against Apple's root, and RevenueCat's `StoreTransaction` keeps
    /// `jwsRepresentation` internal. An auto-renewable subscription stays in
    /// `currentEntitlements` for as long as it runs, so this works regardless of
    /// which service made the purchase.
    private func attestPlus() async {
        guard let attestor, tier == .plus else { return }
        for await result in StoreKit.Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  Self.subscriptions.contains(transaction.productID),
                  transaction.revocationDate == nil else { continue }
            if let expiry = transaction.expirationDate, expiry <= Date() { continue }
            let proof = EntitlementProof(
                productID: transaction.productID,
                transactionID: String(transaction.id),
                jws: result.jwsRepresentation
            )
            try? await attestor.attest(proof)
            return
        }
    }

    private static let subscriptions: Set<String> = [ProductID.plusWeekly, ProductID.plusMonthly]

    @discardableResult
    func restore() async throws -> Bool {
        do {
            let info = try await Purchases.shared.restorePurchases()
            setTier(info.entitlements.active[Self.plusEntitlement] != nil ? .plus : .free)
        } catch {
            switch Self.code(of: error) {
            // The user closed Apple's sheet themselves — not a failure, and not
            // something the room needs words for (audit M-7).
            case .purchaseCancelledError: throw CommerceError.cancelled
            case .offlineConnectionError, .networkError: throw CommerceError.offline
            default: throw CommerceError.offline
            }
        }
        await attestPlus()
        // Read straight off this actor, never off a racing entitlement stream: the
        // Bool is the whole difference between "The binding holds" and "No binding
        // was found", and it must not outrun the receipt.
        return tier == .plus
    }

    // MARK: - Buying

    func purchase(_ productID: String) async throws -> PurchaseOutcome {
        // Purchase the PACKAGE, never a bare StoreProduct. The Package carries its
        // `presentedOfferingContext` — offering, placement, targeting revision and
        // experiment variant — into the transaction, and buying around it silently
        // opts the app out of every experiment it is enrolled in.
        guard let package = try await package(for: productID) else {
            throw CommerceError.productUnavailable(productID)
        }
        do {
            let result = try await Purchases.shared.purchase(package: package)
            if result.userCancelled { return .cancelled }
            setTier(result.customerInfo.entitlements.active[Self.plusEntitlement] != nil ? .plus : .free)

            if ProductID.consumables.contains(productID) {
                try await deliverVials(productID: productID, transaction: result.transaction)
            } else {
                await attestPlus()
            }
            return .success
        } catch {
            switch Self.code(of: error) {
            case .purchaseCancelledError: return .cancelled
            // Ask to Buy / SCA. Nothing is entitled yet, and treating this as
            // success is how a child ends up with Plus a parent never approved.
            case .paymentPendingError: return .pending
            case .productNotAvailableForPurchaseError, .productAlreadyPurchasedError:
                throw CommerceError.productUnavailable(productID)
            case .offlineConnectionError, .networkError: throw CommerceError.offline
            default: throw error is CommerceError ? error : CommerceError.unverified
            }
        }
    }

    /// Sends a verified consumable to the server-side wallet.
    ///
    /// The receipt comes from StoreKit rather than from RevenueCat's transaction,
    /// because the proxy verifies an Apple signature chain and RevenueCat does not
    /// expose one. `Transaction.latest(for:)` is the same call RevenueCat's own
    /// `recordPurchase(productID:)` makes, and it is matched against the transaction
    /// id RevenueCat reported so a stale receipt for an older pack cannot be
    /// mistaken for this purchase.
    ///
    /// Throwing here is what turns a network failure into "try again in a moment"
    /// rather than "you paid and got nothing" — and the proxy's webhook route is
    /// what eventually makes the credits arrive anyway.
    private func deliverVials(productID: String, transaction: StoreTransaction?) async throws {
        guard let delivery else { throw CommerceError.deliveryPending }
        guard let verification = await StoreKit.Transaction.latest(for: productID),
              case .verified(let signed) = verification,
              transaction.map({ String(signed.id) == $0.transactionIdentifier }) ?? true
        else {
            // RevenueCat took the payment and its backend has the transaction, so
            // the webhook will still credit this. Nothing is lost — it simply is
            // not instant, and the room must say so rather than claim success.
            throw CommerceError.deliveryPending
        }
        do {
            try await delivery.deliver(VialGrant(
                productID: productID,
                transactionID: String(signed.id),
                jws: verification.jwsRepresentation
            ))
            for continuation in grantObservers.values { continuation.yield(()) }
        } catch let error as ProxyError {
            throw Self.deliveryError(for: error)
        } catch {
            throw CommerceError.deliveryPending
        }
    }

    /// 4xx application answers are TERMINAL — an invalid, revoked or
    /// already-redeemed receipt can never succeed however often it is retried
    /// (audit M-4). A rate limit is 4xx on the wire and transient in nature, so it
    /// retries; so does everything 5xx, offline or transport-shaped.
    private static func deliveryError(for error: ProxyError) -> CommerceError {
        switch error {
        case .server(let status) where (400..<500).contains(status): .deliveryRejected
        case .moderated, .paymentRequired: .deliveryRejected
        case .rateLimited, .offline, .transport, .server, .badResponse, .cancelled: .deliveryPending
        }
    }

    // MARK: - Pricing

    func products(for ids: [String]) async -> [String: StorePrice] {
        await refreshOfferingsIfEmpty()
        // Anything the Offering does not carry is fetched directly, once, in one
        // round trip. Ids the storefront does not answer for are simply ABSENT from
        // the result, so callers keep their last known values.
        let missing = ids.filter { packages[$0] == nil && looseProducts[$0] == nil }
        if !missing.isEmpty {
            for product in await Purchases.shared.products(missing) {
                looseProducts[product.productIdentifier] = product
            }
        }
        return ids.reduce(into: [:]) { quotes, id in
            guard let product = packages[id]?.storeProduct ?? looseProducts[id] else { return }
            quotes[id] = StorePrice(display: product.localizedPriceString, amount: product.price)
        }
    }

    func isEligibleForIntroOffer(_ productID: String) async -> Bool? {
        let eligibility = await Purchases.shared
            .checkTrialOrIntroDiscountEligibility(productIdentifiers: [productID])
        // `.unknown` must stay nil. Answering false strips a trial the user is
        // entitled to; answering true promises one they will be charged for
        // instead, which is a 3.1.2 rejection and a broken promise (C-2).
        switch eligibility[productID]?.status {
        case .eligible: return true
        case .ineligible, .noIntroOfferExists: return false
        case .unknown, .none: return nil
        @unknown default: return nil
        }
    }

    /// The Offering as last fetched, for the paywall's impression event and for
    /// reading experiment metadata. Nil until `start()` has answered.
    func currentOffering() -> Offering? { offering }

    // MARK: - Internals

    private func apply(_ info: CustomerInfo) async {
        // Covers renewal, expiry, refund, family-sharing revocation and a restore
        // performed on another device — every one of them takes Plus away or gives
        // it back on the next tick, with nothing entitlement-shaped persisted here.
        setTier(info.entitlements.active[Self.plusEntitlement] != nil ? .plus : .free)
    }

    private func package(for productID: String) async throws -> Package? {
        await refreshOfferingsIfEmpty()
        return packages[productID]
    }

    private func refreshOfferingsIfEmpty() async {
        guard packages.isEmpty else { return }
        await refreshOfferings()
    }

    /// RevenueCat throws `PublicError`, which is an `NSError` carrying an
    /// `ErrorCode` raw value — not a Swift error you can pattern-match directly.
    /// The domain check matters: a URLSession failure surfacing through the same
    /// call must not be read as a purchase cancellation.
    private static func code(of error: Error) -> ErrorCode? {
        let nsError = error as NSError
        guard nsError.domain == ErrorCode.errorDomain else { return nil }
        return ErrorCode(rawValue: nsError.code)
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
        // The immediate yield is load-bearing: `AppModel.tier` is written from this
        // stream and nothing else, so a subscriber that hears nothing until the
        // first change leaves a paying user on the free tier until they renew.
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

/// Reports a StoreKit purchase the app made itself to RevenueCat.
///
/// Only used while `LiveCommerce.backend` is `.storeKit` and RevenueCat runs in
/// `.myApp` mode. RevenueCat's own observer-mode detector polls `Transaction.all`
/// and posts only the single most recent verified transaction while marking every
/// unsynced id as synced — so two purchases landing between passes lose the older
/// one permanently. Calling this per purchase is the documented way to not care.
protocol PurchaseRecording: Sendable {
    func record(_ result: Product.PurchaseResult) async
}

struct RevenueCatPurchaseRecorder: PurchaseRecording {
    func record(_ result: Product.PurchaseResult) async {
        // Best-effort by design: this is bookkeeping for the dashboard, and a
        // failure here must never affect whether the user got what they paid for.
        _ = try? await Purchases.shared.recordPurchase(result)
    }
}
