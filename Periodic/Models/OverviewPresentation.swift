import Foundation

enum OverviewSortOption: String, CaseIterable, Identifiable {
    case remainingDaysDescending
    case remainingDaysAscending
    case nameAscending
    case expiryAscending
    case expiryDescending
    case amountAscending
    case amountDescending

    var id: String { rawValue }

    var title: String {
        switch self {
        case .remainingDaysDescending: AppLocalization.string("剩余天数（多到少）")
        case .remainingDaysAscending: AppLocalization.string("剩余天数（少到多）")
        case .nameAscending: AppLocalization.string("名称（A–Z）")
        case .expiryAscending: AppLocalization.string("到期日（近到远）")
        case .expiryDescending: AppLocalization.string("到期日（远到近）")
        case .amountAscending: AppLocalization.string("金额（低到高）")
        case .amountDescending: AppLocalization.string("金额（高到低）")
        }
    }

    func sorted(_ items: [SubscriptionListItem], referenceDate: LocalDate) -> [SubscriptionListItem] {
        items.sorted { lhs, rhs in
            let comparison = compare(lhs, rhs, referenceDate: referenceDate)
            if comparison != .orderedSame { return comparison == .orderedAscending }
            let nameComparison = lhs.name.localizedStandardCompare(rhs.name)
            if nameComparison != .orderedSame { return nameComparison == .orderedAscending }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private func compare(
        _ lhs: SubscriptionListItem,
        _ rhs: SubscriptionListItem,
        referenceDate: LocalDate
    ) -> ComparisonResult {
        switch self {
        case .remainingDaysDescending:
            return compareOptional(
                lhs.remainingDayCount(relativeTo: referenceDate),
                rhs.remainingDayCount(relativeTo: referenceDate),
                ascending: false
            )
        case .remainingDaysAscending:
            return compareOptional(
                lhs.remainingDayCount(relativeTo: referenceDate),
                rhs.remainingDayCount(relativeTo: referenceDate),
                ascending: true
            )
        case .nameAscending:
            return lhs.name.localizedStandardCompare(rhs.name)
        case .expiryAscending:
            return compareOptional(lhs.expiry, rhs.expiry, ascending: true)
        case .expiryDescending:
            return compareOptional(lhs.expiry, rhs.expiry, ascending: false)
        case .amountAscending:
            return compareMoney(lhs.money, rhs.money, ascending: true)
        case .amountDescending:
            return compareMoney(lhs.money, rhs.money, ascending: false)
        }
    }

    private func compareMoney(_ lhs: Money, _ rhs: Money, ascending: Bool) -> ComparisonResult {
        if lhs.currency != rhs.currency {
            return lhs.currency.rawValue.localizedStandardCompare(rhs.currency.rawValue)
        }
        return compareValues(lhs.minorUnits, rhs.minorUnits, ascending: ascending)
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
}

enum OverviewColumnPreferences {
    private static let noOptionalColumns = "__none__"

    static func visibleColumns(from rawValue: String) -> Set<OverviewTextColumn> {
        guard !rawValue.isEmpty else { return Set(OverviewTextColumn.allCases) }
        guard rawValue != noOptionalColumns else { return [] }
        return Set(rawValue.split(separator: ",").compactMap {
            OverviewTextColumn(rawValue: String($0))
        })
    }

    static func storedValue(for columns: Set<OverviewTextColumn>) -> String {
        guard !columns.isEmpty else { return noOptionalColumns }
        return OverviewTextColumn.allCases
            .filter(columns.contains)
            .map(\.rawValue)
            .joined(separator: ",")
    }
}

enum OverviewSelection {
    static func visibleIDs(
        in selection: Set<SubscriptionListItem.ID>,
        items: [SubscriptionListItem]
    ) -> Set<SubscriptionListItem.ID> {
        selection.intersection(items.map(\.id))
    }
}
