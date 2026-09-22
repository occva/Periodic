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
}
