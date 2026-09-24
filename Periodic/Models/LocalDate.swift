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

    var iso8601Text: String {
        let components = dateComponents
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    init(iso8601Text: String) throws {
        let parts = iso8601Text.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]),
              let date = Self.utcGregorian.date(
                from: DateComponents(year: year, month: month, day: day)
              ) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: [], debugDescription: "Invalid Gregorian date")
            )
        }
        self.init(date, calendar: Self.utcGregorian)
        guard self.iso8601Text == iso8601Text else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: [], debugDescription: "Invalid Gregorian date")
            )
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(iso8601Text: container.decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(iso8601Text)
    }

    func date(calendar: Calendar = .current) -> Date {
        var localGregorian = Calendar(identifier: .gregorian)
        localGregorian.timeZone = calendar.timeZone
        return localGregorian.date(from: dateComponents) ?? Self.epoch
    }

    func addingDays(_ days: Int) -> LocalDate? {
        let (value, overflow) = dayNumber.addingReportingOverflow(days)
        return overflow ? nil : LocalDate(dayNumber: value)
    }

    func addingMonths(_ months: Int) -> LocalDate? {
        guard months >= 0 else { return nil }
        let components = dateComponents
        guard let year = components.year,
              let month = components.month,
              let day = components.day else {
            return nil
        }
        let (zeroBasedMonth, monthOverflow) = (month - 1).addingReportingOverflow(months)
        guard !monthOverflow else { return nil }
        let (targetYear, yearOverflow) = year.addingReportingOverflow(zeroBasedMonth / 12)
        guard !yearOverflow else { return nil }
        let targetMonth = zeroBasedMonth % 12 + 1
        guard let firstOfTargetMonth = Self.utcGregorian.date(
            from: DateComponents(year: targetYear, month: targetMonth, day: 1)
        ), let dayRange = Self.utcGregorian.range(of: .day, in: .month, for: firstOfTargetMonth),
              let target = Self.utcGregorian.date(
                from: DateComponents(
                    year: targetYear,
                    month: targetMonth,
                    day: min(day, dayRange.count)
                )
              ) else {
            return nil
        }
        return LocalDate(target, calendar: Self.utcGregorian)
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
