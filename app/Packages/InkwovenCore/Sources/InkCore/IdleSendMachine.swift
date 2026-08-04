import Foundation

public enum SendState: Equatable, Sendable {
    case idle
    case inking
    case resting(since: Date)
    case speculating(since: Date)
    case committed
    case cancelled
    /// "The page waits" (task B5): idle-send is paused entirely — no tick
    /// ever commits until the hold is released.
    case held
}

public enum SendEvent: Equatable, Sendable {
    case strokeBegan
    case strokeEnded(at: Date)
    case tick(now: Date)
    case uploadStarted
    case uploadFinished
    /// Tool-tray hold: enters `.held`; a second toggle releases to `.idle`
    /// (the shell re-feeds `strokeEnded` if unsent ink is waiting, resuming
    /// the normal rest cadence).
    case holdToggled
    /// Tool-tray cancel: from resting/speculating → `.cancelled`, aborting
    /// any speculative upload. Ink is retained.
    case cancelRequested
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

    /// Timings are candidates for server tuning (GateConfig), so a bad pair
    /// must degrade, never trap. Negatives clamp to zero; an inverted pair
    /// (speculateAfter >= commitAfter) is honored as-is and simply means the
    /// send commits without ever speculating — the tick order in `handle`
    /// checks `commitAfter` first, so no upload is ever left orphaned.
    public init(speculateAfter: TimeInterval = 2.0, commitAfter: TimeInterval = 3.0) {
        self.speculateAfter = max(0, speculateAfter)
        self.commitAfter = max(0, commitAfter)
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

        // Hold — "the page waits". Entering from speculating aborts the
        // speculative upload; nothing may be in flight while held. Strokes
        // during a hold keep the state held (writing continues; sending
        // stays paused). Release returns to idle; the shell resumes the
        // rest cadence by re-feeding strokeEnded when unsent ink waits.
        case (.held, .holdToggled):
            state = .idle
            return []

        case (.speculating, .holdToggled):
            state = .held
            let hadUpload = speculativeUploadOutstanding
            speculativeUploadOutstanding = false
            return hadUpload ? [.abortUpload] : []

        // `.committed` included (audit D-9): with no transition here, hold
        // pressed while an exchange streamed fell through to `default`, and
        // the shell's release branch then RE-ARMED the cadence — the exact
        // opposite of what the button says. The in-flight exchange itself is
        // the shell's to manage; holding only pauses further sending.
        case (.idle, .holdToggled), (.inking, .holdToggled),
             (.resting, .holdToggled), (.cancelled, .holdToggled),
             (.committed, .holdToggled):
            state = .held
            return []

        case (.held, .strokeBegan), (.held, .strokeEnded), (.held, .tick):
            return []

        // Cancel send — only meaningful while a send is pending.
        case (.speculating, .cancelRequested):
            state = .cancelled
            speculativeUploadOutstanding = false
            return [.abortUpload]

        case (.resting, .cancelRequested):
            state = .cancelled
            return []

        // The shell abandons an in-flight exchange (page torn down, draft
        // erased mid-stream): the machine must not stay `.committed`, or the
        // next stroke resumes a cycle that belongs to a dead exchange.
        case (.committed, .cancelRequested):
            state = .cancelled
            return []

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
