import Foundation

enum ManagementState: String, CaseIterable, Identifiable, Codable, Sendable {
    case active
    case inactive

    var id: String { rawValue }
    var title: String {
        switch self {
        case .active: AppLocalization.string("使用中")
        case .inactive: AppLocalization.string("已停用")
        }
    }
}

enum BillingKind: String, CaseIterable, Identifiable, Codable, Sendable {
    case recurring
    case lifetime

    var id: String { rawValue }
    var title: String {
        AppLocalization.string(self == .recurring ? "周期订阅" : "终生购买")
    }
}

enum BillingCycle: Int, CaseIterable, Identifiable, Codable, Sendable {
    case monthly = 1
    case quarterly = 3
    case semiannual = 6
    case annual = 12

    var id: Int { rawValue }
    var title: String {
        switch self {
        case .monthly: AppLocalization.string("月度")
        case .quarterly: AppLocalization.string("季度")
        case .semiannual: AppLocalization.string("半年")
        case .annual: AppLocalization.string("年度")
        }
    }
}

enum ServiceCategory: String, CaseIterable, Identifiable, Codable, Sendable {
    case workStudy
    case tools
    case media
    case household
    case communication
    case food
    case other

    var id: String { rawValue }
    var title: String {
        switch self {
        case .workStudy: AppLocalization.string("工作学习")
        case .tools: AppLocalization.string("工具产品")
        case .media: AppLocalization.string("影音娱乐")
        case .household: AppLocalization.string("家庭日常")
        case .communication: AppLocalization.string("通讯服务")
        case .food: AppLocalization.string("餐饮零食")
        case .other: AppLocalization.string("其他")
        }
    }
}

enum CurrencyCode: String, CaseIterable, Identifiable, Codable, Sendable {
    case cny = "CNY"
    case usd = "USD"
    case jpy = "JPY"
    case kwd = "KWD"

    var id: String { rawValue }
    var scale: Int {
        switch self {
        case .jpy: 0
        case .kwd: 3
        case .cny, .usd: 2
        }
    }
}
