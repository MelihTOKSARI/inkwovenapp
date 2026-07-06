import Foundation
import InkCore

public enum Tier: String, Codable, Sendable {
    case free
    case plus
}

/// Snapshot of the user's entitlements. RevenueCat is the source of truth for
/// `tier`; usage counters are server-authoritative (the proxy tracks them) —
/// this snapshot is the client's cache for offline UX and is reconciled on
/// every exchange. Client-side clocks never grant capacity.
public struct EntitlementSnapshot: Equatable, Sendable {
    public var tier: Tier
    public var momentsUsedToday: Int
    public var imagesUsedToday: Int
    public var memoryEnabled: Bool

    public init(tier: Tier, momentsUsedToday: Int = 0, imagesUsedToday: Int = 0, memoryEnabled: Bool = false) {
        self.tier = tier
        self.momentsUsedToday = momentsUsedToday
        self.imagesUsedToday = imagesUsedToday
        self.memoryEnabled = memoryEnabled
    }

    public var archiveWindowDays: Int? { tier == .plus ? nil : 30 } // nil = unlimited
}

/// Server-tunable knobs, fetched from `GET /v1/config` — cap and cooldown
/// curve change without an app release.
public struct GateConfig: Equatable, Sendable, Codable {
    public var freeMomentsPerDay: Int
    public var plusImageDailySoftCap: Int
    /// Cooldown per image past the soft cap; the last entry repeats.
    public var cooldownCurveSeconds: [Double]

    public init(
        freeMomentsPerDay: Int = 5,
        plusImageDailySoftCap: Int = 20,
        cooldownCurveSeconds: [Double] = [60, 300, 900, 3600]
    ) {
        self.freeMomentsPerDay = freeMomentsPerDay
        self.plusImageDailySoftCap = plusImageDailySoftCap
        self.cooldownCurveSeconds = cooldownCurveSeconds
    }
}

public enum PaywallTrigger: String, Sendable {
    case moments
    case archive
    case memory
}

public enum GateDecision: Equatable, Sendable {
    case allow
    /// In-fiction paywall ("bind the notebook to you") — always after a value
    /// moment, never at onboarding.
    case paywall(PaywallTrigger)
    /// Plus soft cap: "the ink must rest" — growing cooldowns, never a hard error.
    case cooldown(seconds: Double)
}

/// Gate order is a must-test invariant: `canSend` runs BEFORE any model call.
public enum SendGate {
    public static func canSend(
        modality: Modality,
        snapshot: EntitlementSnapshot,
        config: GateConfig = GateConfig()
    ) -> GateDecision {
        switch snapshot.tier {
        case .free:
            // Free: 5 magic moments/day across all modalities; the 6th shows
            // the paywall before any model call.
            if snapshot.momentsUsedToday >= config.freeMomentsPerDay {
                return .paywall(.moments)
            }
            return .allow

        case .plus:
            // Plus: unlimited ink. Images past the daily soft cap slow down
            // in fiction with a growing cooldown — never a hard error.
            guard modality == .image else { return .allow }
            let overage = snapshot.imagesUsedToday - config.plusImageDailySoftCap
            guard overage >= 0 else { return .allow }
            let curve = config.cooldownCurveSeconds
            guard !curve.isEmpty else { return .allow }
            return .cooldown(seconds: curve[min(overage, curve.count - 1)])
        }
    }

    /// Reopening a page older than the archive window is a paywall trigger.
    public static func canOpenPage(ageDays: Int, snapshot: EntitlementSnapshot) -> GateDecision {
        if let window = snapshot.archiveWindowDays, ageDays > window {
            return .paywall(.archive)
        }
        return .allow
    }

    /// Invoking memory ("the notebook wants to remember this…") on free tier.
    public static func canUseMemory(snapshot: EntitlementSnapshot) -> GateDecision {
        snapshot.memoryEnabled ? .allow : .paywall(.memory)
    }
}
