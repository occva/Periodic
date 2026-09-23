import Foundation

struct LocalDate: Hashable, Comparable, Codable, Sendable {
    let dayNumber: Int

    /// Default end shown when creating a lifetime history period.
    static let defaultLifetimeHistoryEnd = LocalDate(dayNumber: 47_481) // 2099-12-31

    init(dayNumber: Int) {
        self.dayNumber = dayNumber
    }

    init(_ date: Date, calendar: Calendar = .current) {
        var localGregorian = Calendar(identifier: .gregorian)
        localGregorian.timeZone = calendar.timeZone
        let components = localGregorian.dateComponents([.year, .month, .day], from: date)
        let normalized = Self.utcGregorian.date(from: components)
        dayNumber = normalized.flatMap {
            Self.utcGregorian.dateComponents([.day], from: Self.epoch, to: $0).day
        } ?? 0
    }

    static var today: LocalDate { LocalDate(Date()) }

    static func < (lhs: LocalDate, rhs: LocalDate) -> Bool {
        lhs.dayNumber < rhs.dayNumber
    }

    var displayText: String {
        let components = dateComponents
        return String(format: "%04d/%02d/%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    func date(calendar: Calendar = .current) -> Date {
        var localGregorian = Calendar(identifier: .gregorian)
        localGregorian.timeZone = calendar.timeZone
        return localGregorian.date(from: dateComponents) ?? Self.epoch
    }

    private var dateComponents: DateComponents {
        let date = Self.utcGregorian.date(byAdding: .day, value: dayNumber, to: Self.epoch)
            ?? Self.epoch
        return Self.utcGregorian.dateComponents([.year, .month, .day], from: date)
    }

    private static var utcGregorian: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }

    private static var epoch: Date {
        utcGregorian.date(from: DateComponents(year: 1970, month: 1, day: 1))
            ?? Date(timeIntervalSince1970: 0)
    }
}
