import Foundation

/// StoreKit product identifiers (configured in RevenueCat; task A4).
public enum ProductID {
    public static let plusMonthly = "plus_monthly_9_99"
    /// 7-day trial attaches to annual.
    public static let plusAnnual = "plus_annual_59_99"

    public static let credits10 = "credits_10"
    public static let credits30 = "credits_30"
    public static let credits100 = "credits_100"

    public static let consumables: Set<String> = [credits10, credits30, credits100]

    public static func creditAmount(for productID: String) -> Int? {
        switch productID {
        case credits10: 10
        case credits30: 30
        case credits100: 100
        default: nil
        }
    }
}

/// Boundary to the RevenueCat SDK; the live adapter lives in the app target
/// (SDK dependency stays out of the pure packages). Emits a fresh snapshot on
/// every customer-info change, including restore/refund/expiry (task G3).
public protocol EntitlementProviding: Sendable {
    func currentSnapshot() async -> EntitlementSnapshot
    func snapshots() -> AsyncStream<EntitlementSnapshot>
}
