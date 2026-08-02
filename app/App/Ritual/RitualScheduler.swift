@preconcurrency import UserNotifications
import Foundation
import InkCore

/// Authorization as the ritual reads it — the app's own vocabulary, so no
/// screen or model has to import UserNotifications to ask where it stands.
enum RitualAuthorization: Equatable {
    case notDetermined
    case granted
    case denied
}

/// The narrow slice of the notification centre the ritual needs. Traffics in
/// `RitualNight` values, never UN types, so a fake is a handful of arrays and
/// the system's own objects stay behind the live conformance.
@MainActor
protocol RitualNotificationCenter: AnyObject {
    func authorization() async -> RitualAuthorization
    /// Asks for `.alert` and `.sound` only — never `.badge`; a badge count
    /// reads like unread email, which is wrong for a notebook.
    func requestAuthorization() async -> Bool
    func add(_ night: RitualNight) async
    /// Pending identifiers under the ritual's prefix — never anyone else's.
    func pendingRitualIdentifiers() async -> [String]
    func removePending(identifiers: [String])
}

/// Where any page last archived — the day only, never content or Book. The
/// Keeper's writes count without breaking its seal: the ritual must stay
/// silent on a day the user wrote, whichever Book kept the page.
@MainActor
protocol RitualDiary: AnyObject {
    var lastWrittenAt: Date? { get }
}

extension PageArchive: RitualDiary {}

/// Arms and disarms the week of evening reminders. Replaces the pending set
/// wholesale on every re-arm, so the queue can never grow past the planner's
/// horizon or carry a stale night.
@MainActor
final class RitualScheduler {
    private let center: any RitualNotificationCenter

    init(center: any RitualNotificationCenter = UserNotificationRitualCenter()) {
        self.center = center
    }

    func authorization() async -> RitualAuthorization {
        await center.authorization()
    }

    func requestAuthorization() async -> Bool {
        await center.requestAuthorization()
    }

    func schedule(_ nights: [RitualNight]) async {
        await cancelAll()
        for night in nights.prefix(RitualPlanner.horizonNights) {
            await center.add(night)
        }
    }

    func cancelAll() async {
        let pending = await center.pendingRitualIdentifiers()
        guard !pending.isEmpty else { return }
        center.removePending(identifiers: pending)
    }
}

/// Live conformance over `UNUserNotificationCenter`.
@MainActor
final class UserNotificationRitualCenter: RitualNotificationCenter {
    static let authorizationOptions: UNAuthorizationOptions = [.alert, .sound]

    private let center = UNUserNotificationCenter.current()

    func authorization() async -> RitualAuthorization {
        switch await center.notificationSettings().authorizationStatus {
        case .notDetermined: .notDetermined
        case .denied: .denied
        default: .granted
        }
    }

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: Self.authorizationOptions)) ?? false
    }

    func add(_ night: RitualNight) async {
        try? await center.add(Self.request(for: night))
    }

    func pendingRitualIdentifiers() async -> [String] {
        await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(RitualPlanner.identifierPrefix) }
    }

    func removePending(identifiers: [String]) {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    /// The one place a night becomes a system request. A calendar trigger over
    /// the night's wall-clock components — never a time-interval trigger, an
    /// absolute date, or a badge.
    static func request(for night: RitualNight) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = night.title
        content.body = night.body
        content.sound = .default
        content.userInfo = [RitualPlanner.bookUserInfoKey: night.book.rawValue]
        return UNNotificationRequest(
            identifier: night.identifier,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: night.fire, repeats: false)
        )
    }
}
