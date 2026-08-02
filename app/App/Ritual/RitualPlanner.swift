import Foundation
import InkCore

/// One planned night of the ritual — everything a notification request needs,
/// as a value. `fire` carries wall-clock components only (year, month, day,
/// hour, minute) and never a `TimeZone`: a zone captured at scheduling time is
/// a bug that only shows up when someone flies somewhere. The calendar trigger
/// resolves the components in whatever zone the device is in when the night
/// arrives.
struct RitualNight: Equatable {
    let identifier: String
    let book: BookID
    let title: String
    let body: String
    let fire: DateComponents
}

/// Lays out the week of evening reminders. Pure date math — the scheduler
/// turns nights into system requests, the planner only decides which nights
/// exist and what they say.
enum RitualPlanner {
    /// Seven, deliberately far under the 64 pending requests iOS allows an
    /// app. Re-arming replaces the set rather than growing it; if the app is
    /// never opened the queue simply drains, and a notebook nobody opens
    /// goes quiet.
    static let horizonNights = 7
    static let identifierPrefix = "ritual."
    static let bookUserInfoKey = "ritual.book"

    static func plan(
        now: Date = .now,
        calendar: Calendar = .current,
        hour: Int,
        minute: Int,
        voice: BookID,
        lastWrittenAt: Date?
    ) -> [RitualNight] {
        let wroteToday = lastWrittenAt.map { calendar.isDate($0, inSameDayAs: now) } ?? false
        var nights: [RitualNight] = []
        for offset in 0..<horizonNights {
            guard let day = calendar.date(byAdding: .day, value: offset, to: now) else { continue }
            if offset == 0 {
                // The most important rule: a page already written today keeps
                // tonight silent. A tonight whose hour has already passed is
                // skipped too — a calendar trigger for a past date never
                // fires and would only sit in the pending queue.
                if wroteToday { continue }
                guard let tonight = calendar.date(
                    bySettingHour: hour, minute: minute, second: 0, of: now
                ), tonight > now else { continue }
            }
            let date = calendar.dateComponents([.year, .month, .day], from: day)
            guard let year = date.year, let month = date.month, let dayOfMonth = date.day else {
                continue
            }
            var fire = DateComponents()
            fire.year = year
            fire.month = month
            fire.day = dayOfMonth
            fire.hour = hour
            fire.minute = minute
            let ordinal = calendar.ordinality(of: .day, in: .era, for: day) ?? offset
            nights.append(RitualNight(
                identifier: identifierPrefix + String(format: "%04d-%02d-%02d", year, month, dayOfMonth),
                book: voice,
                title: RitualCopy.title,
                body: RitualCopy.line(for: voice, night: ordinal),
                fire: fire
            ))
        }
        return nights
    }
}
