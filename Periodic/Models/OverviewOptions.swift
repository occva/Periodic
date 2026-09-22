import Foundation

enum SubscriptionQuickView: String, CaseIterable, Identifiable {
    case all
    case active
    case expired
    case inactive
    case lifetime

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: AppLocalization.string("全部项目")
        case .active: AppLocalization.string("使用中")
        case .expired: AppLocalization.string("已过期")
        case .inactive: AppLocalization.string("已停用")
        case .lifetime: AppLocalization.string("终生")
        }
    }
}

enum OverviewGrouping: String, CaseIterable, Identifiable {
    case none
    case category
    case managementState

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: AppLocalization.string("不分组")
        case .category: AppLocalization.string("按服务类型")
        case .managementState: AppLocalization.string("按管理状态")
        }
    }
}

enum OverviewExpiryFilter: String, CaseIterable, Identifiable {
    case all
    case effective
    case expired
    case unknownDate
    case lifetime

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: AppLocalization.string("全部到期状态")
        case .effective: AppLocalization.string("未过期")
        case .expired: AppLocalization.string("已过期")
        case .unknownDate: AppLocalization.string("日期未知")
        case .lifetime: AppLocalization.string("永久有效")
        }
    }
}
