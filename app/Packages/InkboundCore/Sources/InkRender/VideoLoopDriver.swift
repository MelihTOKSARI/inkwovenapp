import Foundation

/// Moving-picture driver (task C5). Clips are ≤5s: download fully, then loop
/// locally (AVPlayerLooper in the shell) — no streaming playback. Failure at
/// any stage emits `.refund` so the credit reservation is released upstream;
/// the user is never charged for a clip that didn't bloom.
public struct VideoLoopDriver: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case idle
        case downloading(remoteURL: URL)
        case looping(localURL: URL)
        case failed
    }

    public enum Event: Equatable, Sendable {
        case start(remoteURL: URL, reservationID: UUID)
        case downloadCompleted(localURL: URL)
        case downloadFailed
        case playbackFailed
    }

    public enum Output: Equatable, Sendable {
        case beginDownload(URL)
        case loop(localURL: URL)
        case settleCredit(reservationID: UUID)
        case refund(reservationID: UUID)
    }

    public private(set) var phase: Phase = .idle
    private var reservationID: UUID?

    public init() {}

    @discardableResult
    public mutating func handle(_ event: Event) -> [Output] {
        switch (phase, event) {
        case (.idle, .start(let remote, let reservation)):
            phase = .downloading(remoteURL: remote)
            reservationID = reservation
            return [.beginDownload(remote)]

        case (.downloading, .downloadCompleted(let local)):
            phase = .looping(localURL: local)
            // The clip is on-page — the credit is spent now, not before.
            guard let reservationID else { return [.loop(localURL: local)] }
            return [.loop(localURL: local), .settleCredit(reservationID: reservationID)]

        case (.downloading, .downloadFailed):
            phase = .failed
            guard let reservationID else { return [] }
            return [.refund(reservationID: reservationID)]

        // Playback failure after a successful download: the credit was
        // legitimately spent (asset delivered); still surface the failure.
        case (.looping, .playbackFailed):
            phase = .failed
            return []

        default:
            return []
        }
    }
}
