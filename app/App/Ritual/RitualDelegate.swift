@preconcurrency import UserNotifications
import InkAnalytics
import InkCore

/// Installed once at launch (AppDI retains it — the centre holds its delegate
/// weakly). Three duties: attribute an app open to the ritual notification
/// that caused it, walk the tap to the Book whose voice spoke it (audit
/// L-18), and keep the banner out of a room the writer is already in.
///
/// `@MainActor` because the route ends at AppModel; the `@preconcurrency`
/// conformance quiets the non-Sendable UN types crossing in — safe, because
/// both requirements here are async, and an async witness always hops to
/// its actor before touching state.
@MainActor
final class RitualNotificationDelegate: NSObject, @preconcurrency UNUserNotificationCenterDelegate {
    private let analytics: Analytics
    /// Where a tapped night leads — bound by the App once the model stands
    /// (DI.routeRitualTaps). The route goes through AppModel's own open flow,
    /// so the Keeper's gate holds; this delegate never bypasses a lock.
    private var onOpen: ((BookID) -> Void)?
    /// A cold-launch tap can be delivered before the route is bound; it waits
    /// here and walks the moment `bind` arrives, rather than vanishing.
    private var pendingBook: BookID?

    init(analytics: Analytics) {
        self.analytics = analytics
    }

    func bind(onOpen: @escaping (BookID) -> Void) {
        self.onOpen = onOpen
        if let book = pendingBook {
            pendingBook = nil
            onOpen(book)
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let request = response.notification.request
        guard request.identifier.hasPrefix(RitualPlanner.identifierPrefix),
              let raw = request.content.userInfo[RitualPlanner.bookUserInfoKey] as? String
        else { return }
        let book = BookID(raw)
        await analytics.track(.ritualOpened(book: book))
        // The tap is a request to open that Book, not just a statistic.
        if let onOpen {
            onOpen(book)
        } else {
            pendingBook = book
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        // The notebook is already open — it does not ask to be opened.
        []
    }
}
