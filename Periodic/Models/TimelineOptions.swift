import Foundation

enum TimelineRange: Int, CaseIterable, Identifiable {
    case oneMonth = 1
    case threeMonths = 3
    case sixMonths = 6
    case oneYear = 12
    case threeYears = 36
    case fiveYears = 60

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .oneMonth: AppLocalization.string("1 月")
        case .threeMonths: AppLocalization.string("3 月")
        case .sixMonths: AppLocalization.string("6 月")
        case .oneYear: AppLocalization.string("1 年")
        case .threeYears: AppLocalization.string("3 年")
        case .fiveYears: AppLocalization.string("5 年")
        }
    }
}

enum TimelinePreferences {
    static let defaultRange = TimelineRange.fiveYears
    static let defaultSortField = TimelineSortField.expiry
    static let defaultSortDirection = TimelineSortDirection.ascending
    static let defaultUpcomingExpanded = true

    static func range(for rawValue: Int) -> TimelineRange {
        TimelineRange(rawValue: rawValue) ?? defaultRange
    }

    static func normalizedRangeRawValue(_ rawValue: Int) -> Int {
        range(for: rawValue).rawValue
    }

    static func sortField(for rawValue: String) -> TimelineSortField {
        TimelineSortField(rawValue: rawValue) ?? defaultSortField
    }

    static func sortDirection(for rawValue: String) -> TimelineSortDirection {
        TimelineSortDirection(rawValue: rawValue) ?? defaultSortDirection
    }

}

enum DueHorizon: Int, CaseIterable, Identifiable, Sendable {
    case sevenDays = 7
    case fifteenDays = 15
    case thirtyDays = 30

    var id: Int { rawValue }
    var title: String {
        String(format: AppLocalization.string("%d 天"), rawValue)
    }
}

enum TimelineSortDirection: String, CaseIterable, Identifiable {
    case ascending
    case descending

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ascending: AppLocalization.string("升序")
        case .descending: AppLocalization.string("降序")
        }
    }

    var symbolName: String {
        switch self {
        case .ascending: "arrow.up"
        case .descending: "arrow.down"
        }
    }
}

enum TimelineSortField: String, CaseIterable, Identifiable {
    case name
    case expiry
    case remainingDays
    case periodStart
    case billingCycle
    case note
    case amount
    case monthlyEstimate
    case annualEstimate
    case category
    case expiryStatus
    case managementState

    var id: String { rawValue }

    var title: String {
        switch self {
        case .name: AppLocalization.string("服务名称")
        case .expiry: AppLocalization.string("到期时间")
        case .remainingDays: AppLocalization.string("剩余时长")
        case .periodStart: AppLocalization.string("订阅时间")
        case .billingCycle: AppLocalization.string("周期")
        case .note: AppLocalization.string("备注")
        case .amount: AppLocalization.string("消费金额")
        case .monthlyEstimate: AppLocalization.string("按月计算")
        case .annualEstimate: AppLocalization.string("按年计算")
        case .category: AppLocalization.string("服务类型")
        case .expiryStatus: AppLocalization.string("状态")
        case .managementState: AppLocalization.string("账户状态")
        }
    }

    var symbolName: String {
        switch self {
        case .name: "textformat"
        case .expiry: "calendar"
        case .remainingDays: "clock"
        case .periodStart: "calendar.badge.clock"
        case .billingCycle: "calendar.circle"
        case .note: "text.bubble"
        case .amount: "banknote"
        case .monthlyEstimate: "sum"
        case .annualEstimate: "sum"
        case .category: "list.bullet"
        case .expiryStatus: "circle.dotted"
        case .managementState: "circle.dashed"
        }
    }

    func sorted(
        _ items: [SubscriptionListItem],
        direction: TimelineSortDirection,
        referenceDate: LocalDate
    ) -> [SubscriptionListItem] {
        items.sorted { lhs, rhs in
            let comparison = compare(
                lhs,
                rhs,
                direction: direction,
                referenceDate: referenceDate
            )
            if comparison != .orderedSame {
                return comparison == .orderedAscending
            }
            let nameComparison = lhs.name.localizedStandardCompare(rhs.name)
            if nameComparison != .orderedSame {
                return nameComparison == .orderedAscending
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private func compare(
        _ lhs: SubscriptionListItem,
        _ rhs: SubscriptionListItem,
        direction: TimelineSortDirection,
        referenceDate: LocalDate
    ) -> ComparisonResult {
        let ascending = direction == .ascending
        switch self {
        case .name:
            return compareStrings(lhs.name, rhs.name, ascending: ascending)
        case .expiry:
            return compareOptional(lhs.expiry, rhs.expiry, ascending: ascending)
        case .remainingDays:
            return compareOptional(
                lhs.remainingDayCount(relativeTo: referenceDate),
                rhs.remainingDayCount(relativeTo: referenceDate),
                ascending: ascending
            )
        case .periodStart:
            return compareOptional(lhs.periodStart, rhs.periodStart, ascending: ascending)
        case .billingCycle:
            return compareOptional(lhs.cycleMonths, rhs.cycleMonths, ascending: ascending)
        case .note:
            return compareOptionalString(lhs.note, rhs.note, ascending: ascending)
        case .amount:
            return compareMoney(lhs.money, rhs.money, ascending: ascending)
        case .monthlyEstimate:
            return compareEstimate(lhs, rhs, annual: false, ascending: ascending)
        case .annualEstimate:
            return compareEstimate(lhs, rhs, annual: true, ascending: ascending)
        case .category:
            return compareValues(
                categoryRank(lhs.categoryValue),
                categoryRank(rhs.categoryValue),
                ascending: ascending
            )
        case .expiryStatus:
            return compareValues(
                statusRank(lhs, referenceDate: referenceDate),
                statusRank(rhs, referenceDate: referenceDate),
                ascending: ascending
            )
        case .managementState:
            return compareValues(
                lhs.managementState == .active ? 0 : 1,
                rhs.managementState == .active ? 0 : 1,
                ascending: ascending
            )
        }
    }

    private func compareEstimate(
        _ lhs: SubscriptionListItem,
        _ rhs: SubscriptionListItem,
        annual: Bool,
        ascending: Bool
    ) -> ComparisonResult {
        if lhs.money.currency != rhs.money.currency {
            return lhs.money.currency.rawValue.localizedStandardCompare(
                rhs.money.currency.rawValue
            )
        }
        let left = lhs.cycleMonths.map {
            annual
                ? lhs.money.annualAmount(cycleMonths: $0)
                : lhs.money.monthlyAmount(cycleMonths: $0)
        }
        let right = rhs.cycleMonths.map {
            annual
                ? rhs.money.annualAmount(cycleMonths: $0)
                : rhs.money.monthlyAmount(cycleMonths: $0)
        }
        return compareOptional(left, right, ascending: ascending)
    }

    private func compareMoney(
        _ lhs: Money,
        _ rhs: Money,
        ascending: Bool
    ) -> ComparisonResult {
        if lhs.currency != rhs.currency {
            return lhs.currency.rawValue.localizedStandardCompare(rhs.currency.rawValue)
        }
        return compareValues(lhs.minorUnits, rhs.minorUnits, ascending: ascending)
    }

    private func compareOptionalString(
        _ lhs: String,
        _ rhs: String,
        ascending: Bool
    ) -> ComparisonResult {
        let left = lhs.trimmingCharacters(in: .whitespacesAndNewlines)
        let right = rhs.trimmingCharacters(in: .whitespacesAndNewlines)
        return switch (left.isEmpty, right.isEmpty) {
        case (false, false): compareStrings(left, right, ascending: ascending)
        case (false, true): .orderedAscending
        case (true, false): .orderedDescending
        case (true, true): .orderedSame
        }
    }

    private func compareStrings(
        _ lhs: String,
        _ rhs: String,
        ascending: Bool
    ) -> ComparisonResult {
        let comparison = lhs.localizedStandardCompare(rhs)
        guard comparison != .orderedSame, !ascending else { return comparison }
        return comparison == .orderedAscending ? .orderedDescending : .orderedAscending
    }

    private func compareOptional<Value: Comparable>(
        _ lhs: Value?,
        _ rhs: Value?,
        ascending: Bool
    ) -> ComparisonResult {
        switch (lhs, rhs) {
        case let (left?, right?): compareValues(left, right, ascending: ascending)
        case (_?, nil): .orderedAscending
        case (nil, _?): .orderedDescending
        case (nil, nil): .orderedSame
        }
    }

    private func compareValues<Value: Comparable>(
        _ lhs: Value,
        _ rhs: Value,
        ascending: Bool
    ) -> ComparisonResult {
        guard lhs != rhs else { return .orderedSame }
        let isAscending = lhs < rhs
        return isAscending == ascending ? .orderedAscending : .orderedDescending
    }

    private func categoryRank(_ category: ServiceCategory) -> Int {
        ServiceCategory.allCases.firstIndex(of: category) ?? .max
    }

    private func statusRank(
        _ item: SubscriptionListItem,
        referenceDate: LocalDate
    ) -> Int {
        if item.managementState == .inactive { return 2 }
        if (item.remainingDayCount(relativeTo: referenceDate) ?? 0) < 0 { return 1 }
        return 0
    }
}
