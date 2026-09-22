import SwiftUI

struct TimelineAxisLayout {
    let start: LocalDate
    let end: LocalDate
    let minorTicks: [LocalDate]
    let majorTicks: [LocalDate]
    let range: TimelineRange

    init(centerDate: Date, range: TimelineRange) {
        let calendar = Calendar.current
        let startDate: Date
        let endDate: Date
        let minorComponent: Calendar.Component
        let minorValue: Int
        let majorComponent: Calendar.Component
        let majorValue: Int

        switch range {
        case .oneMonth:
            startDate = calendar.date(byAdding: .day, value: -15, to: centerDate) ?? centerDate
            endDate = calendar.date(byAdding: .day, value: 15, to: centerDate) ?? centerDate
            minorComponent = .day
            minorValue = 1
            majorComponent = .month
            majorValue = 1
        case .threeMonths:
            startDate = calendar.date(byAdding: .day, value: -45, to: centerDate) ?? centerDate
            endDate = calendar.date(byAdding: .day, value: 45, to: centerDate) ?? centerDate
            minorComponent = .weekOfYear
            minorValue = 1
            majorComponent = .month
            majorValue = 1
        case .sixMonths:
            startDate = calendar.date(byAdding: .month, value: -3, to: centerDate) ?? centerDate
            endDate = calendar.date(byAdding: .month, value: 3, to: centerDate) ?? centerDate
            minorComponent = .weekOfYear
            minorValue = 1
            majorComponent = .month
            majorValue = 1
        case .oneYear:
            startDate = calendar.date(byAdding: .month, value: -6, to: centerDate) ?? centerDate
            endDate = calendar.date(byAdding: .month, value: 6, to: centerDate) ?? centerDate
            minorComponent = .weekOfYear
            minorValue = 1
            majorComponent = .month
            majorValue = 1
        case .threeYears:
            startDate = calendar.date(byAdding: .month, value: -18, to: centerDate) ?? centerDate
            endDate = calendar.date(byAdding: .month, value: 18, to: centerDate) ?? centerDate
            minorComponent = .month
            minorValue = 1
            majorComponent = .year
            majorValue = 1
        case .fiveYears:
            startDate = calendar.date(byAdding: .month, value: -30, to: centerDate) ?? centerDate
            endDate = calendar.date(byAdding: .month, value: 30, to: centerDate) ?? centerDate
            minorComponent = .month
            minorValue = 1
            majorComponent = .year
            majorValue = 1
        }

        start = LocalDate(startDate)
        end = LocalDate(endDate)
        self.range = range
        minorTicks = Self.makeTicks(
            from: startDate,
            through: endDate,
            component: minorComponent,
            value: minorValue,
            calendar: calendar
        )
        majorTicks = Self.makeTicks(
            from: startDate,
            through: endDate,
            component: majorComponent,
            value: majorValue,
            calendar: calendar,
            includeLeadingBoundary: true
        )
    }

    func contains(_ date: LocalDate) -> Bool {
        (start.dayNumber...end.dayNumber).contains(date.dayNumber)
    }

    func x(for date: LocalDate, width: CGFloat) -> CGFloat {
        let span = max(1, end.dayNumber - start.dayNumber)
        let offset = date.dayNumber - start.dayNumber
        return width * CGFloat(offset) / CGFloat(span)
    }

    func majorLabel(for date: LocalDate) -> String {
        let parts = date.displayText.split(separator: "/")
        guard parts.count == 3 else { return date.displayText }
        switch range {
        case .oneMonth, .threeMonths, .sixMonths, .oneYear:
            if date == majorTicks.first || parts[1] == "01" {
                return "\(parts[0])年\(Int(parts[1]) ?? 1)月"
            }
            return "\(Int(parts[1]) ?? 1)月"
        case .threeYears, .fiveYears:
            return "\(parts[0])年"
        }
    }

    func minorLabel(for date: LocalDate) -> String {
        let parts = date.displayText.split(separator: "/")
        guard parts.count == 3 else { return date.displayText }
        switch range {
        case .oneMonth, .threeMonths, .sixMonths, .oneYear:
            return String(Int(parts[2]) ?? 1)
        case .threeYears, .fiveYears:
            return String(Int(parts[1]) ?? 1)
        }
    }

    func todayLabel(for date: LocalDate) -> String {
        let parts = date.displayText.split(separator: "/")
        guard parts.count == 3 else { return date.displayText }
        return String(Int(parts[2]) ?? 1)
    }

    func majorLabelX(for date: LocalDate, width: CGFloat) -> CGFloat {
        guard let index = majorTicks.firstIndex(of: date) else {
            return x(for: date, width: width)
        }
        let nextDayNumber = index + 1 < majorTicks.count
            ? majorTicks[index + 1].dayNumber
            : end.dayNumber
        let midpoint = LocalDate(dayNumber: (date.dayNumber + nextDayNumber) / 2)
        return min(max(x(for: midpoint, width: width), 28), width - 28)
    }

    private static func makeTicks(
        from start: Date,
        through end: Date,
        component: Calendar.Component,
        value: Int,
        calendar: Calendar,
        includeLeadingBoundary: Bool = false
    ) -> [LocalDate] {
        var result: [LocalDate] = []
        var date = alignedStart(for: start, component: component, calendar: calendar)
        if !includeLeadingBoundary, date < start {
            date = calendar.date(byAdding: component, value: value, to: date) ?? start
        }
        while date <= end {
            result.append(LocalDate(date))
            guard let next = calendar.date(byAdding: component, value: value, to: date), next > date else {
                break
            }
            date = next
        }
        return result
    }

    private static func alignedStart(
        for date: Date,
        component: Calendar.Component,
        calendar: Calendar
    ) -> Date {
        switch component {
        case .day:
            return calendar.startOfDay(for: date)
        case .weekOfYear, .month, .year:
            return calendar.dateInterval(of: component, for: date)?.start ?? date
        default:
            return date
        }
    }
}
