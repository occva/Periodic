import Foundation

struct LocalDate: Hashable, Comparable, Codable, Sendable {
    let dayNumber: Int

    init(dayNumber: Int) {
        self.dayNumber = dayNumber
    }

    init(_ date: Date, calendar: Calendar = .current) {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        let normalized = utc.date(from: components) ?? Date(timeIntervalSince1970: 0)
        dayNumber = Int(normalized.timeIntervalSince1970 / 86_400)
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
        calendar.date(from: dateComponents) ?? Date(timeIntervalSince1970: 0)
    }

    private var dateComponents: DateComponents {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = Date(timeIntervalSince1970: TimeInterval(dayNumber * 86_400))
        return utc.dateComponents([.year, .month, .day], from: date)
    }
}
