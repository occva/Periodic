import Foundation

struct SubscriptionNotificationSchedule: Equatable, Sendable {
    static let defaultAdvanceDays = [1]
    static let defaultMinuteOfDay = 9 * 60
    static let defaultStoredAdvanceDays = "1"

    let advanceDays: [Int]
    let minuteOfDay: Int

    init(advanceDays: [Int], minuteOfDay: Int) {
        self.advanceDays = Self.normalizedAdvanceDays(advanceDays)
        self.minuteOfDay = Self.normalizedMinuteOfDay(minuteOfDay)
    }

    init?(
        reminderDate: Date,
        expiry: LocalDate,
        calendar: Calendar = .current
    ) {
        let reminderDay = LocalDate(reminderDate, calendar: calendar)
        guard reminderDay <= expiry else { return nil }
        let components = calendar.dateComponents([.hour, .minute], from: reminderDate)
        self.init(
            advanceDays: [expiry.dayNumber - reminderDay.dayNumber],
            minuteOfDay: (components.hour ?? 9) * 60 + (components.minute ?? 0)
        )
    }

    static var `default`: SubscriptionNotificationSchedule {
        SubscriptionNotificationSchedule(
            advanceDays: defaultAdvanceDays,
            minuteOfDay: defaultMinuteOfDay
        )
    }

    static func resolvingEditorSchedule(
        initial: SubscriptionNotificationSchedule,
        edited: SubscriptionNotificationSchedule,
        isModified: Bool
    ) -> SubscriptionNotificationSchedule {
        isModified ? edited : initial
    }

    static func normalizedAdvanceDays(_ days: [Int]) -> [Int] {
        Array(Set(days.filter { $0 >= 0 })).sorted(by: >)
    }

    static func storedAdvanceDays(_ days: [Int]) -> String {
        normalizedAdvanceDays(days).map(String.init).joined(separator: ",")
    }

    static func advanceDays(from storedValue: String) -> [Int] {
        let parsed = storedValue
            .split(separator: ",")
            .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        return parsed.isEmpty ? defaultAdvanceDays : normalizedAdvanceDays(parsed)
    }

    static func normalizedMinuteOfDay(_ value: Int) -> Int {
        min(max(value, 0), 23 * 60 + 59)
    }

    func reminderDate(
        relativeTo expiryDate: Date,
        calendar: Calendar = .current
    ) -> Date {
        let expiryStart = calendar.startOfDay(for: expiryDate)
        let reminderStart = calendar.date(
            byAdding: .day,
            value: -(advanceDays.first ?? Self.defaultAdvanceDays[0]),
            to: expiryStart
        ) ?? expiryStart
        return calendar.date(
            byAdding: .minute,
            value: minuteOfDay,
            to: reminderStart
        ) ?? reminderStart
    }

    static func adjustedCustomReminderDate(
        current: Date,
        previousExpiryDate: Date,
        expiryDate: Date,
        followsExpiry: Bool,
        calendar: Calendar = .current
    ) -> Date {
        let latestDate = calendar.date(
            bySettingHour: 23,
            minute: 59,
            second: 59,
            of: expiryDate
        ) ?? expiryDate
        guard followsExpiry || current > latestDate else { return current }
        if followsExpiry,
           let schedule = SubscriptionNotificationSchedule(
               reminderDate: current,
               expiry: LocalDate(previousExpiryDate, calendar: calendar),
               calendar: calendar
           ) {
            return schedule.reminderDate(relativeTo: expiryDate, calendar: calendar)
        }
        return Self.default.reminderDate(relativeTo: expiryDate, calendar: calendar)
    }
}
