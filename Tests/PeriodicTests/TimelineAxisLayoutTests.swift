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

    @Test func futureEventLabelDoesNotCrossTodayMarker() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
        let todayDate = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 10, day: 4, hour: 12))
        )
        let today = LocalDate(todayDate, calendar: calendar)
        let expiry = LocalDate(dayNumber: today.dayNumber + 2)
        let layout = TimelineAxisLayout(centerDate: todayDate, range: .threeYears)
        let todayX = layout.x(for: today, width: 1_000)
        let expiryX = layout.x(for: expiry, width: 1_000)
        let futurePlacement = TimelineEventPlacement(
            anchorX: expiryX,
            viewportWidth: 1_000
        )

        #expect(futurePlacement.direction == .trailing)
        #expect(abs(futurePlacement.leadingX - expiryX) < 0.001)
        #expect(futurePlacement.leadingX > todayX)

        let nearRightEdgePlacement = TimelineEventPlacement(
            anchorX: 980,
            viewportWidth: 1_000
        )

        #expect(nearRightEdgePlacement.direction == .leading)
        #expect(nearRightEdgePlacement.trailingX == 980)
    }

    @Test func timelineSortSupportsTimeCostMetadataAndStatusFields() throws {
        let referenceDate = try LocalDate(iso8601Text: "2026-10-04")
        let expired = makeItem(
            name: "Expired",
            category: .tools,
            state: .active,
            periodStart: try LocalDate(iso8601Text: "2026-09-01"),
            expiry: try LocalDate(iso8601Text: "2026-09-30"),
            cycleMonths: 1,
            amountMinor: 700,
            note: ""
        )
        let future = makeItem(
            name: "Future",
            category: .media,
            state: .active,
            periodStart: try LocalDate(iso8601Text: "2025-10-10"),
            expiry: try LocalDate(iso8601Text: "2026-10-10"),
            cycleMonths: 12,
            amountMinor: 12_000,
            note: "B"
        )
        let inactive = makeItem(
            name: "Inactive",
            category: .household,
            state: .inactive,
            periodStart: try LocalDate(iso8601Text: "2026-09-01"),
            expiry: try LocalDate(iso8601Text: "2026-12-01"),
            cycleMonths: 3,
            amountMinor: 300,
            note: "A"
        )
        let items = [inactive, future, expired]

        #expect(
            TimelineSortField.expiryStatus.sorted(
                items,
                direction: .ascending,
                referenceDate: referenceDate
            ).map(\.name) == ["Future", "Expired", "Inactive"]
        )
        #expect(
            TimelineSortField.remainingDays.sorted(
                items,
                direction: .ascending,
                referenceDate: referenceDate
            ).map(\.name) == ["Expired", "Future", "Inactive"]
        )
        #expect(
            TimelineSortField.monthlyEstimate.sorted(
                items,
                direction: .ascending,
                referenceDate: referenceDate
            ).map(\.name) == ["Inactive", "Expired", "Future"]
        )
        #expect(
            TimelineSortField.note.sorted(
                items,
                direction: .ascending,
                referenceDate: referenceDate
            ).map(\.name) == ["Inactive", "Future", "Expired"]
        )
        #expect(
            TimelineSortField.name.sorted(
                items,
                direction: .descending,
                referenceDate: referenceDate
            ).map(\.name) == ["Inactive", "Future", "Expired"]
        )
    }

    @Test func timelinePreferencesRejectUnknownStoredSortValues() {
        #expect(TimelinePreferences.sortField(for: "unknown") == .expiry)
        #expect(TimelinePreferences.sortDirection(for: "unknown") == .ascending)
        #expect(TimelinePreferences.defaultUpcomingExpanded)
    }

    private func makeItem(
        name: String,
        category: ServiceCategory,
        state: ManagementState,
        periodStart: LocalDate,
        expiry: LocalDate,
        cycleMonths: Int,
        amountMinor: Int64,
        note: String
    ) -> SubscriptionListItem {
        SubscriptionListItem(dto: SubscriptionDTO(
            id: UUID(),
            name: name,
            symbolName: "calendar",
            iconResourceName: nil,
            iconURLString: nil,
            category: category,
            managementState: state,
            billingKind: .recurring,
            periodStart: periodStart,
            expiry: expiry,
            cycleMonths: cycleMonths,
            money: Money(minorUnits: amountMinor, currency: .cny),
            note: note,
            reminderEnabled: false,
            revision: 1,
            createdAt: Date(),
            updatedAt: Date()
        ))
    }
}
