@preconcurrency import UserNotifications
import InkAnalytics
import InkCore

/// Installed once at launch (AppDI retains it — the centre holds its delegate
/// weakly). Two duties: attribute an app open to the ritual notification that
/// caused it, and keep the banner out of a room the writer is already in.
final class RitualNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    private let analytics: Analytics

    init(analytics: Analytics) {
        self.analytics = analytics
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let request = response.notification.request
        guard request.identifier.hasPrefix(RitualPlanner.identifierPrefix),
              let raw = request.content.userInfo[RitualPlanner.bookUserInfoKey] as? String
        else { return }
        await analytics.track(.ritualOpened(book: BookID(raw)))
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        // The notebook is already open — it does not ask to be opened.
        []
    }
}
