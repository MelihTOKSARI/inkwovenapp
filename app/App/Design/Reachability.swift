import Foundation
import Network
import Observation

/// Whether the room can reach anything at all.
///
/// `ProxyError.offline` and `InFictionState.pageIsQuiet` both exist, but the
/// page collapses every failure into one decline card, so a writer on the
/// Tube spends the whole rest window and a send attempt only to be told the
/// spirit is distant — with a retry button that will fail identically every
/// time. This says so *before* the ink is committed, and it does it without
/// reaching into the exchange path.
@Observable
@MainActor
final class Reachability {
    static let shared = Reachability()

    private(set) var isOffline = false
    private let monitor = NWPathMonitor()

    private init() {
        monitor.pathUpdateHandler = { path in
            let offline = path.status != .satisfied
            Task { @MainActor [weak self] in
                self?.isOffline = offline
            }
        }
        monitor.start(queue: DispatchQueue(label: "ink.reachability", qos: .utility))
    }
}
