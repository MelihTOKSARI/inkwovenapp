import Foundation

/// StoreKit product identifiers (configured in App Store Connect; task A4).
/// Permanent once submitted — deliberately no embedded prices.
public enum ProductID {
    /// 3-day free trial attaches to weekly.
    public static let plusWeekly = "plus_weekly"
    public static let plusMonthly = "plus_monthly"

    // The Vials — moving-picture credits. Named by SIZE, never by quantity or
    // price: a consumable id is as permanent as a subscription id, and
    // `credits_10` becomes a lie the first time a pack changes from 10 to 8.
    // Sizes and prices live in design/app-store-assets/credits.md §3.
    public static let vialsSmall = "vials_small"
    public static let vialsMedium = "vials_medium"
    public static let vialsLarge = "vials_large"

    public static let consumables: Set<String> = [vialsSmall, vialsMedium, vialsLarge]

    /// Display order for the shop — smallest first, best value last.
    public static let vialPacks: [String] = [vialsSmall, vialsMedium, vialsLarge]

    /// How many clips a pack carries. This is the CLIENT's copy, used to label
    /// the shop; the wallet is credited by the server from its own map, so a
    /// tampered client can inflate a label and nothing else.
    public static func creditAmount(for productID: String) -> Int? {
        switch productID {
        case vialsSmall: 3
        case vialsMedium: 8
        case vialsLarge: 20
        default: nil
        }
    }
}

/// A verified consumable purchase, on its way to the server-side wallet.
/// Carries the receipt rather than an amount: what a pack is worth is the
/// proxy's decision, so a tampered client cannot mint itself credits.
public struct VialGrant: Equatable, Sendable {
    public var productID: String
    public var transactionID: String
    public var jws: String

    public init(productID: String, transactionID: String, jws: String) {
        self.productID = productID
        self.transactionID = transactionID
        self.jws = jws
    }
}

/// Delivers a verified purchase to the wallet that actually spends it.
///
/// The wallet is server-side, so a purchase is not complete when StoreKit says
/// so — it is complete when the proxy has credited it. Delivery must therefore
/// be awaited BEFORE the transaction is finished: an unfinished transaction is
/// redelivered on the next launch, a finished one is gone for good. Throwing
/// here is how a network failure turns into "try again later" instead of
/// "the user paid and got nothing".
public protocol VialGrantDelivering: Sendable {
    func deliver(_ grant: VialGrant) async throws
}

/// Boundary to the RevenueCat SDK; the live adapter lives in the app target
/// (SDK dependency stays out of the pure packages). Emits a fresh snapshot on
/// every customer-info change, including restore/refund/expiry (task G3).
public protocol EntitlementProviding: Sendable {
    func currentSnapshot() async -> EntitlementSnapshot
    func snapshots() -> AsyncStream<EntitlementSnapshot>
}
