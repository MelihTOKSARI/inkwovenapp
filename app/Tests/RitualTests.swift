import Testing
import Foundation
import UserNotifications
@testable import Inkwoven
import InkCore

/// The evening ritual (task H2): seven wall-clock nights, replaced wholesale
/// on every re-arm, silenced by a page written today, and gone entirely when
/// the toggle or the permission says no.
@MainActor
@Suite("Evening ritual")
struct RitualTests {
    /// A fixed calendar so the plan is the same on every machine that runs
    /// this; the components the planner emits carry no zone regardless.
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        return calendar
    }()
    /// A weekday morning, hours before the default eight-in-the-evening.
    private static let morning = calendar.date(
        from: DateComponents(year: 2026, month: 8, day: 3, hour: 9, minute: 0)
    )!

    private func makeModel(
        center: FakeRitualCenter,
        diary: (any RitualDiary)? = nil,
        seed: ((UserDefaults) -> Void)? = nil
    ) -> AppModel {
        let suite = UserDefaults(suiteName: "ink.tests.\(UUID().uuidString)")!
        seed?(suite)
        return AppModel(
            defaults: suite,
            purchases: UnboundPurchaseService(),
            ritual: RitualScheduler(center: center),
            ritualDiary: diary
        )
    }

    private func seedArmed(_ suite: UserDefaults) {
        suite.set(true, forKey: "ink.ritualAsked")
        suite.set(true, forKey: "ink.ritualEnabled")
    }

    // MARK: - Planning

    @Test("a morning plan lays out seven nights with distinct dated identifiers")
    func sevenDistinctNights() throws {
        let nights = RitualPlanner.plan(
            now: Self.morning, calendar: Self.calendar,
            hour: 20, minute: 0, voice: .oracle, lastWrittenAt: nil
        )
        #expect(nights.count == 7)
        #expect(Set(nights.map(\.identifier)).count == 7, "every night carries its own identifier")
        #expect(nights.first?.identifier == "ritual.2026-08-03")
        #expect(nights.last?.identifier == "ritual.2026-08-09")
        for night in nights {
            #expect(night.identifier.hasPrefix(RitualPlanner.identifierPrefix))
            #expect(night.fire.hour == 20)
            #expect(night.fire.minute == 0)
        }
    }

    @Test("copy rotates so no two consecutive nights say the same thing")
    func copyVariesNightToNight() {
        let nights = RitualPlanner.plan(
            now: Self.morning, calendar: Self.calendar,
            hour: 20, minute: 0, voice: .storyteller, lastWrittenAt: nil
        )
        for (tonight, tomorrow) in zip(nights, nights.dropFirst()) {
            #expect(tonight.body != tomorrow.body, "adjacent nights may never repeat a line")
        }
        #expect(Set(nights.map(\.body)).count >= 4, "a four-line pool spreads across the week")
        #expect(nights.allSatisfy { $0.title == RitualCopy.title }, "the title stays constant and plain")
    }

    @Test("a page written today silences tonight and leaves the rest of the week intact")
    func wroteTodaySuppressesTonightOnly() {
        let dawnPage = Self.calendar.date(byAdding: .hour, value: -3, to: Self.morning)
        let nights = RitualPlanner.plan(
            now: Self.morning, calendar: Self.calendar,
            hour: 20, minute: 0, voice: .keeper, lastWrittenAt: dawnPage
        )
        #expect(nights.count == 6)
        #expect(nights.first?.identifier == "ritual.2026-08-04", "tonight is the one night missing")

        let yesterdayPage = Self.calendar.date(byAdding: .day, value: -1, to: Self.morning)
        let unsuppressed = RitualPlanner.plan(
            now: Self.morning, calendar: Self.calendar,
            hour: 20, minute: 0, voice: .keeper, lastWrittenAt: yesterdayPage
        )
        #expect(unsuppressed.count == 7, "yesterday's page has no claim on tonight")
    }

    @Test("an hour already past schedules nothing for tonight")
    func passedHourSkipsTonight() {
        let lateEvening = Self.calendar.date(
            from: DateComponents(year: 2026, month: 8, day: 3, hour: 21, minute: 30)
        )!
        let nights = RitualPlanner.plan(
            now: lateEvening, calendar: Self.calendar,
            hour: 20, minute: 0, voice: .oracle, lastWrittenAt: nil
        )
        #expect(nights.count == 6)
        #expect(nights.first?.identifier == "ritual.2026-08-04")
    }

    // MARK: - Requests

    @Test("a request is a calendar trigger over bare wall-clock components — no zone, no absolute date, no badge")
    func wallClockRequestsOnly() throws {
        let nights = RitualPlanner.plan(
            now: Self.morning, calendar: Self.calendar,
            hour: 20, minute: 0, voice: .gameMaster, lastWrittenAt: nil
        )
        for night in nights {
            #expect(night.fire.timeZone == nil, "a TimeZone captured at scheduling time breaks on the first flight")
            let request = UserNotificationRitualCenter.request(for: night)
            let trigger = try #require(request.trigger as? UNCalendarNotificationTrigger)
            #expect(trigger.dateComponents.timeZone == nil)
            #expect(trigger.repeats == false)
            #expect(request.content.badge == nil, "no badge, ever — a badge reads like unread email")
            #expect(request.content.userInfo[RitualPlanner.bookUserInfoKey] as? String == BookID.gameMaster.rawValue)
        }
        #expect(!UserNotificationRitualCenter.authorizationOptions.contains(.badge))
    }

    // MARK: - Arming

    @Test("re-arming replaces stale requests and never exceeds the seven-night horizon")
    func rearmReplacesStale() async {
        let center = FakeRitualCenter(status: .granted)
        center.pending = ["ritual.2020-01-01", "ritual.2020-01-02", "other.system"]
        let model = makeModel(center: center) { seedArmed($0) }

        await model.rearmRitual(now: Self.morning, calendar: Self.calendar)

        let ritualPending = center.pending.filter { $0.hasPrefix("ritual.") }
        #expect(ritualPending.count == 7)
        #expect(!ritualPending.contains("ritual.2020-01-01"), "stale nights are gone")
        #expect(center.pending.contains("other.system"), "nothing outside the ritual's prefix is touched")
    }

    @Test("toggling the ritual off cancels everything pending")
    func toggleOffCancelsAll() async {
        let center = FakeRitualCenter(status: .granted)
        let model = makeModel(center: center) { seedArmed($0) }
        await model.rearmRitual(now: Self.morning, calendar: Self.calendar)
        #expect(!center.pending.isEmpty)

        model.ritualEnabled = false
        await model.ritualTask?.value

        #expect(center.pending.isEmpty)
        #expect(!model.ritualEffectivelyOn)
    }

    @Test("denied authorization schedules nothing and the toggle reads off")
    func deniedSchedulesNothing() async {
        let center = FakeRitualCenter(status: .denied)
        let model = makeModel(center: center) { seedArmed($0) }

        await model.rearmRitual(now: Self.morning, calendar: Self.calendar)

        #expect(center.added.isEmpty)
        #expect(center.pending.isEmpty)
        #expect(model.ritualAuthorization == .denied)
        #expect(!model.ritualEffectivelyOn, "the Drawer's toggle must show the device's truth")
    }

    @Test("changing the hour reschedules the whole week against it")
    func timeChangeReschedules() async {
        let center = FakeRitualCenter(status: .granted)
        let model = makeModel(center: center) { seedArmed($0) }
        await model.rearmRitual(now: Self.morning, calendar: Self.calendar)
        #expect(center.added.allSatisfy { $0.fire.hour == 20 })

        let nineOClock = Self.calendar.date(
            from: DateComponents(year: 2026, month: 8, day: 3, hour: 21, minute: 15)
        )!
        model.setRitualTime(from: nineOClock, calendar: Self.calendar)
        await model.ritualTask?.value
        await model.rearmRitual(now: Self.morning, calendar: Self.calendar)

        #expect(model.ritualHour == 21)
        #expect(model.ritualMinute == 15)
        #expect(!center.added.isEmpty)
        #expect(center.added.allSatisfy { $0.fire.hour == 21 && $0.fire.minute == 15 })
    }

    // MARK: - Permission

    @Test("the system is asked exactly once, and a grant turns the ritual on")
    func askedExactlyOnce() async {
        let center = FakeRitualCenter(status: .notDetermined, grantOnRequest: true)
        let model = makeModel(center: center)

        let first = await model.promptRitualIfNeeded()
        #expect(first == true)
        #expect(model.ritualEnabled, "the ritual defaults on once permission is granted")
        #expect(model.ritualAuthorization == .granted)

        let second = await model.promptRitualIfNeeded()
        #expect(second == nil, "re-triggering the ask does nothing")
        #expect(center.requestCount == 1)
    }

    @Test("a denial leaves the ritual silently off, and the refusal is remembered across launches")
    func denialStaysOff() async {
        let suite = UserDefaults(suiteName: "ink.tests.\(UUID().uuidString)")!
        let center = FakeRitualCenter(status: .notDetermined, grantOnRequest: false)
        let model = AppModel(
            defaults: suite, purchases: UnboundPurchaseService(),
            ritual: RitualScheduler(center: center), ritualDiary: nil
        )

        let answer = await model.promptRitualIfNeeded()
        #expect(answer == false)
        #expect(!model.ritualEnabled)
        #expect(suite.bool(forKey: "ink.ritualAsked"), "the asked-once flag survives relaunch")

        let relaunched = AppModel(
            defaults: suite, purchases: UnboundPurchaseService(),
            ritual: RitualScheduler(center: center), ritualDiary: nil
        )
        let again = await relaunched.promptRitualIfNeeded()
        #expect(again == nil)
        #expect(center.requestCount == 1)
    }

    // MARK: - Voice

    @Test("the ritual speaks as the Book last opened, and as the Keeper before any history")
    func voiceFollowsLastOpenedBook() async {
        let center = FakeRitualCenter(status: .granted)
        let model = makeModel(center: center) { seedArmed($0) }
        #expect(model.ritualVoice == .keeper, "no history yet — the Keeper speaks")

        model.open(book: Book.by(id: .tutor))
        #expect(model.ritualVoice == .tutor)

        await model.ritualTask?.value
        await model.rearmRitual(now: Self.morning, calendar: Self.calendar)
        #expect(center.added.allSatisfy { $0.book == .tutor })
    }
}

// MARK: - Doubles

@MainActor
private final class FakeRitualCenter: RitualNotificationCenter {
    var status: RitualAuthorization
    var grantOnRequest: Bool
    var requestCount = 0
    var added: [RitualNight] = []
    var pending: [String] = []

    init(status: RitualAuthorization, grantOnRequest: Bool = false) {
        self.status = status
        self.grantOnRequest = grantOnRequest
    }

    func authorization() async -> RitualAuthorization { status }

    func requestAuthorization() async -> Bool {
        requestCount += 1
        if status == .notDetermined {
            status = grantOnRequest ? .granted : .denied
        }
        return status == .granted
    }

    func add(_ night: RitualNight) async {
        added.append(night)
        pending.append(night.identifier)
    }

    func pendingRitualIdentifiers() async -> [String] {
        pending.filter { $0.hasPrefix(RitualPlanner.identifierPrefix) }
    }

    func removePending(identifiers: [String]) {
        pending.removeAll { identifiers.contains($0) }
        added.removeAll { identifiers.contains($0.identifier) }
    }
}
