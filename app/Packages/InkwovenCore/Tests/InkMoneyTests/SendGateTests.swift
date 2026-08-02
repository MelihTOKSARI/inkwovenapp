import Foundation
import Testing
import InkCore
@testable import InkMoney

@Suite("SendGate — gate order runs before any model call (task G1)")
struct SendGateTests {
    @Test("free user's 6th moment of the day → paywall, no model call")
    func freeSixthMomentPaywalls() {
        let snapshot = EntitlementSnapshot(tier: .free, momentsUsedToday: 5)
        #expect(SendGate.canSend(modality: .ink, snapshot: snapshot) == .paywall(.moments))
    }

    @Test("free user's 5th moment still flows")
    func freeFifthMomentAllowed() {
        let snapshot = EntitlementSnapshot(tier: .free, momentsUsedToday: 4)
        #expect(SendGate.canSend(modality: .ink, snapshot: snapshot) == .allow)
        #expect(SendGate.canSend(modality: .image, snapshot: snapshot) == .allow)
    }

    @Test("Plus ink is unlimited")
    func plusInkUnlimited() {
        let snapshot = EntitlementSnapshot(tier: .plus, momentsUsedToday: 500, imagesUsedToday: 500)
        #expect(SendGate.canSend(modality: .ink, snapshot: snapshot) == .allow)
    }

    @Test("Plus 9th image of the day → 'the ink must rest' cooldown, never an error")
    func plusImageSoftCapCoolsDown() {
        let snapshot = EntitlementSnapshot(tier: .plus, imagesUsedToday: 8)
        #expect(SendGate.canSend(modality: .image, snapshot: snapshot) == .cooldown(seconds: 60))
    }

    @Test("cooldown grows along the server curve and clamps at the end")
    func cooldownCurveGrowsAndClamps() {
        let config = GateConfig(cooldownCurveSeconds: [60, 300, 900, 3600])
        #expect(SendGate.canSend(modality: .image,
                                 snapshot: EntitlementSnapshot(tier: .plus, imagesUsedToday: 9),
                                 config: config) == .cooldown(seconds: 300))
        #expect(SendGate.canSend(modality: .image,
                                 snapshot: EntitlementSnapshot(tier: .plus, imagesUsedToday: 99),
                                 config: config) == .cooldown(seconds: 3600))
    }

    @Test("Plus image under the cap flows")
    func plusImageUnderCapAllowed() {
        let snapshot = EntitlementSnapshot(tier: .plus, imagesUsedToday: 7)
        #expect(SendGate.canSend(modality: .image, snapshot: snapshot) == .allow)
    }

    @Test("cap and curve are server-tunable without a release")
    func serverTunableConfig() {
        let tuned = GateConfig(freeMomentsPerDay: 3, plusImageDailySoftCap: 10, cooldownCurveSeconds: [10])
        #expect(SendGate.canSend(modality: .ink,
                                 snapshot: EntitlementSnapshot(tier: .free, momentsUsedToday: 3),
                                 config: tuned) == .paywall(.moments))
        #expect(SendGate.canSend(modality: .image,
                                 snapshot: EntitlementSnapshot(tier: .plus, imagesUsedToday: 10),
                                 config: tuned) == .cooldown(seconds: 10))
    }

    @Test("reopening a >30-day page paywalls free, never Plus")
    func archiveWindowGate() {
        #expect(SendGate.canOpenPage(ageDays: 31, snapshot: EntitlementSnapshot(tier: .free)) == .paywall(.archive))
        #expect(SendGate.canOpenPage(ageDays: 30, snapshot: EntitlementSnapshot(tier: .free)) == .allow)
        #expect(SendGate.canOpenPage(ageDays: 400, snapshot: EntitlementSnapshot(tier: .plus)) == .allow)
    }

    @Test("memory invocation paywalls without the entitlement")
    func memoryGate() {
        #expect(SendGate.canUseMemory(snapshot: EntitlementSnapshot(tier: .free)) == .paywall(.memory))
        #expect(SendGate.canUseMemory(snapshot: EntitlementSnapshot(tier: .plus, memoryEnabled: true)) == .allow)
    }
}
