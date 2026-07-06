import Foundation

public enum SendState: Equatable, Sendable {
    case idle
    case inking
    case resting(since: Date)
    case speculating(since: Date)
    case committed
    case cancelled
}

public enum SendEvent: Equatable, Sendable {
    case strokeBegan
    case strokeEnded(at: Date)
    case tick(now: Date)
    case uploadStarted
    case uploadFinished
}

/// Side effects the shell must perform. The machine itself owns no timers and
/// no network — the shell feeds it clock + stroke events, so every acceptance
/// criterion is deterministic.
public enum SendEffect: Equatable, Sendable {
    case beginSpeculativeUpload
    case commitSend
    case abortUpload
}

/// Idle-send state machine (tasks B2/B4):
/// pen rest ≥ `speculateAfter` (2s) → speculative upload; rest ≥ `commitAfter`
/// (3s) → the send commits (exactly once). A new stroke before commit cancels
/// the send and aborts any speculative upload — no model call is ever billed
/// for a cancelled send.
public struct IdleSendMachine: Equatable, Sendable {
    public private(set) var state: SendState = .idle
    public let speculateAfter: TimeInterval
    public let commitAfter: TimeInterval

    /// True between `.beginSpeculativeUpload` and the upload finishing/aborting.
    private var speculativeUploadOutstanding = false

    public init(speculateAfter: TimeInterval = 2.0, commitAfter: TimeInterval = 3.0) {
        precondition(speculateAfter < commitAfter, "speculation must precede commit")
        self.speculateAfter = speculateAfter
        self.commitAfter = commitAfter
    }

    @discardableResult
    public mutating func handle(_ event: SendEvent) -> [SendEffect] {
        switch (state, event) {
        case (.idle, .strokeBegan), (.committed, .strokeBegan):
            state = .inking
            return []

        // `cancelled` means the user interrupted a pending send and is inking
        // again — it behaves like `inking` for the strokes that follow.
        case (.cancelled, .strokeBegan):
            return []

        case (.inking, .strokeEnded(let at)), (.cancelled, .strokeEnded(let at)):
            state = .resting(since: at)
            return []

        case (.resting(let since), .tick(let now)):
            let rested = now.timeIntervalSince(since)
            if rested >= commitAfter {
                // Ticks jumped straight past the speculation window; commit
                // directly — the shell uploads inline with the model call.
                state = .committed
                return [.commitSend]
            }
            if rested >= speculateAfter {
                state = .speculating(since: since)
                speculativeUploadOutstanding = true
                return [.beginSpeculativeUpload]
            }
            return []

        case (.speculating(let since), .tick(let now)):
            if now.timeIntervalSince(since) >= commitAfter {
                state = .committed
                return [.commitSend]
            }
            return []

        case (.resting, .strokeBegan):
            state = .cancelled
            return []

        case (.speculating, .strokeBegan):
            state = .cancelled
            speculativeUploadOutstanding = false
            return [.abortUpload]

        case (_, .uploadStarted):
            return []

        case (_, .uploadFinished):
            speculativeUploadOutstanding = false
            return []

        default:
            return []
        }
    }

    /// Shell calls this after a committed exchange resolves, readying the
    /// machine for the next page interaction.
    public mutating func reset() {
        state = .idle
        speculativeUploadOutstanding = false
    }
}
