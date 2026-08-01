import Foundation
import InkCore
import InkNet

/// The speculative-upload half of the page's send loop: the snapshot uploaded
/// at the rest mark, the ticket it resolves to, and the handoff of that ticket
/// to the exchange that commits.
///
/// It is its own object because the upload `Task` used to be untracked and the
/// ticket assignment unguarded. An upload that resolved AFTER its exchange had
/// already committed — a slow round trip against a 1.5s window — wrote a stale
/// ticket that `abortUpload` could no longer reach, and the NEXT commit sent
/// it. The server then resolved the PREVIOUS page's snapshot and the Book
/// answered ink the user had already had answered, with the new page's ink
/// never uploaded at all. Every upload now carries a generation, and any
/// completion whose generation has moved on is discarded and aborted.
@MainActor
final class SpeculativeUpload {
    private let proxy: any ExchangeProxying
    /// Reports upload start/finish to the send machine, which owns the
    /// `.uploadStarted` / `.uploadFinished` transitions.
    private let onStateChange: @MainActor (SendEvent) -> Void

    /// Bumped by every begin, abort and commit. A completion carrying a stale
    /// mark belongs to a window that has closed.
    private var generation = 0
    private var task: Task<Void, Never>?
    private(set) var payload: SnapshotPayload?
    private(set) var ticket: UploadTicket?

    init(
        proxy: any ExchangeProxying,
        onStateChange: @escaping @MainActor (SendEvent) -> Void
    ) {
        self.proxy = proxy
        self.onStateChange = onStateChange
    }

    /// Pre-pays the network cost at the rest mark. The server never bills an
    /// uncommitted ticket.
    func begin(_ payload: SnapshotPayload) {
        closeWindow()
        self.payload = payload
        let mark = generation
        onStateChange(.uploadStarted)
        task = Task { [weak self, proxy] in
            let resolved = try? await proxy.preupload(payload)
            guard let self, self.generation == mark else {
                // The window closed while this was in flight. Hand the ticket
                // straight back rather than leaving it to expire — and never
                // let it reach the next page.
                if let resolved { await proxy.abort(resolved) }
                return
            }
            self.ticket = resolved
            self.task = nil
            self.onStateChange(.uploadFinished)
        }
    }

    /// The pending send was cancelled, the page turned, or a remembered page
    /// was reopened: discard the snapshot and give any ticket back.
    func abort() {
        let outstanding = ticket
        closeWindow()
        guard let outstanding else { return }
        Task { [proxy] in await proxy.abort(outstanding) }
    }

    /// Hands the resolved ticket to the exchange that is committing and closes
    /// the window, so a later completion cannot reattach to it.
    func takeCommitted() -> UploadTicket? {
        let committed = ticket
        closeWindow()
        return committed
    }

    private func closeWindow() {
        task?.cancel()
        task = nil
        generation &+= 1
        payload = nil
        ticket = nil
    }
}
