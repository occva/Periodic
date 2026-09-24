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

    static func range(for rawValue: Int) -> TimelineRange {
        TimelineRange(rawValue: rawValue) ?? defaultRange
    }

    static func normalizedRangeRawValue(_ rawValue: Int) -> Int {
        range(for: rawValue).rawValue
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
