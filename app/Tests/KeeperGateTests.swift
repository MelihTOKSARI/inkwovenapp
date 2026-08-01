import Testing
import Foundation
import PencilKit
import InkCore
@testable import Inkwoven

/// The Keeper's lock must fail CLOSED. Every outcome the device can hand back
/// other than a successful evaluation leaves the Book shut — including the
/// case that used to open it, `canEvaluatePolicy` returning false on a device
/// with no passcode and no enrolled biometry.
@MainActor
@Suite("Keeper gate")
struct KeeperGateTests {
    // MARK: - Doubles

    struct ScriptedAuth: KeeperAuthenticating {
        let outcome: KeeperAuthOutcome

        func authenticate(reason: String) async -> KeeperAuthOutcome { outcome }
    }

    private func freshModel() -> AppModel {
        let suite = UserDefaults(suiteName: "keeper-gate-\(UUID().uuidString)")!
        let model = AppModel(defaults: suite)
        model.activeBookID = .keeper
        return model
    }

    private func freshArchive() -> PageArchive {
        let dir = URL.temporaryDirectory.appending(path: "keeper-gate-\(UUID().uuidString)")
        return PageArchive(directory: dir)
    }

    /// Mirrors KeeperGateView.unlock()'s decision without standing up a view:
    /// the gate opens on `.granted` and on nothing else.
    private func attempt(
        _ outcome: KeeperAuthOutcome, model: AppModel, archive: PageArchive
    ) async {
        let auth: any KeeperAuthenticating = ScriptedAuth(outcome: outcome)
        if await auth.authenticate(reason: "test") == .granted {
            model.keeperUnlocked = true
            archive.unsealKeeper()
            model.open(book: model.activeBook)
        }
    }

    // MARK: - Fail closed

    @Test("no passcode and no biometry (canEvaluatePolicy false) must NOT open the Keeper")
    func unavailableDenies() async throws {
        let model = freshModel()
        let archive = freshArchive()

        await attempt(.unavailable, model: model, archive: archive)

        #expect(model.keeperUnlocked == false)
        #expect(model.screen != .page)
        #expect(archive.keeperUnsealed == false)
    }

    @Test("an evaluation failure must NOT open the Keeper")
    func deniedDenies() async throws {
        let model = freshModel()
        let archive = freshArchive()

        await attempt(.denied, model: model, archive: archive)

        #expect(model.keeperUnlocked == false)
        #expect(archive.keeperUnsealed == false)
    }

    @Test("a cancelled look and a biometry lockout must NOT open the Keeper")
    func cancelAndLockoutDeny() async throws {
        for outcome in [KeeperAuthOutcome.cancelled, .lockedOut] {
            let model = freshModel()
            let archive = freshArchive()

            await attempt(outcome, model: model, archive: archive)

            #expect(model.keeperUnlocked == false, "\(outcome) must leave the Book shut")
            #expect(archive.keeperUnsealed == false)
        }
    }

    @Test("every refusal carries in-fiction copy; a grant carries none")
    func refusalCopy() throws {
        for outcome in [KeeperAuthOutcome.cancelled, .unavailable, .lockedOut, .denied] {
            let line = KeeperGateView.refusalLine(outcome)
            #expect(line?.isEmpty == false, "\(outcome) needs something to say")
        }
        #expect(KeeperGateView.refusalLine(.granted) == nil)
    }

    // MARK: - Grant

    @Test("success opens the Book that was asked for, not a hardcoded Keeper")
    func grantOpensRequestedBook() async throws {
        let model = freshModel()
        let archive = freshArchive()

        await attempt(.granted, model: model, archive: archive)

        #expect(model.keeperUnlocked)
        #expect(model.screen == .page)
        #expect(model.activeBookID == .keeper)
        #expect(archive.keeperUnsealed)
    }

    @Test("a second locked Book opens itself, not the Keeper")
    func grantDoesNotRedirectToKeeper() async throws {
        let model = freshModel()
        let archive = freshArchive()
        model.activeBookID = .tutor

        await attempt(.granted, model: model, archive: archive)

        #expect(model.activeBookID == .tutor)
        #expect(model.screen == .page)
    }
}
