import Foundation
import LocalAuthentication

/// What the lock made of the hand it was shown. Distinct cases so the gate
/// can speak differently about a look the reader called off, a lock with no
/// key cut for it yet, and a face the lock refused.
enum KeeperAuthOutcome: Equatable, Sendable {
    case granted
    /// The reader dismissed the prompt, or the system took the screen away.
    case cancelled
    /// No passcode and no enrolled biometry on this device — there is nothing
    /// for the lock to know. The Keeper stays shut.
    case unavailable
    /// Too many failed looks; the device passcode has to wake it.
    case lockedOut
    case denied
}

/// The Keeper's lock, behind a seam so the fail-closed contract is testable
/// without a device. The live adapter is bound in App/DI.swift.
@MainActor
protocol KeeperAuthenticating {
    func authenticate(reason: String) async -> KeeperAuthOutcome
}

/// LocalAuthentication adapter. Never returns `.granted` on any path other
/// than a successful evaluation — a lock that opens when it cannot recognise
/// anyone is not a lock. `.deviceOwnerAuthentication` carries the system's
/// own passcode fallback inside the prompt, which is why the gate offers one
/// door and no separate "use passcode" button (audit L-20).
struct LiveKeeperAuth: KeeperAuthenticating {
    func authenticate(reason: String) async -> KeeperAuthOutcome {
        // A fresh context per attempt: LAContext caches a successful
        // evaluation, so reusing one would let a single look open the
        // Keeper again later in the session.
        let context = LAContext()
        var probe: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &probe) else {
            // No passcode set, biometry unavailable, or biometry locked out on
            // a device with no owner credential. There is nothing to
            // authenticate against, so the only safe answer is no.
            return .unavailable
        }
        return await withCheckedContinuation { continuation in
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, error in
                let outcome: KeeperAuthOutcome
                if success {
                    outcome = .granted
                } else {
                    switch (error as? LAError)?.code {
                    case .userCancel, .appCancel, .systemCancel:
                        outcome = .cancelled
                    case .biometryNotEnrolled, .biometryNotAvailable, .passcodeNotSet:
                        outcome = .unavailable
                    case .biometryLockout:
                        outcome = .lockedOut
                    default:
                        outcome = .denied
                    }
                }
                continuation.resume(returning: outcome)
            }
        }
    }
}
