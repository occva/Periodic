import Foundation
import Testing
@testable import Periodic

struct TimelineAxisLayoutTests {
    @Test func todayMarkerAlwaysUsesDayOfMonth() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let centerDate = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 9, day: 22, hour: 12))
        )
        let today = LocalDate(centerDate, calendar: calendar)

        for range in TimelineRange.allCases {
            let layout = TimelineAxisLayout(centerDate: centerDate, range: range)
            #expect(layout.todayLabel(for: today) == "22")
        }

        let fiveYearLayout = TimelineAxisLayout(centerDate: centerDate, range: .fiveYears)
        #expect(fiveYearLayout.minorLabel(for: today) == "9")
    }

    @Test func horizontalScrollMapsViewportDistanceToVisibleDateRange() {
        let layout = TimelineAxisLayout(centerDate: Date(), range: .sixMonths)
        let visibleDayCount = layout.end.dayNumber - layout.start.dayNumber

        #expect(
            layout.dayOffset(forHorizontalScroll: -1_600, viewportWidth: 1_600)
                == Double(visibleDayCount)
        )
        #expect(layout.dayOffset(forHorizontalScroll: 20, viewportWidth: 0) == 0)
    }
}
