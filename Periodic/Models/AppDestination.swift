import Foundation

enum AppDestination: String, CaseIterable, Identifiable {
    case dashboard
    case timeline
    case overview
    case templates

    var id: String { rawValue }
    var title: String {
        switch self {
        case .dashboard: AppLocalization.string("首页")
        case .timeline: AppLocalization.string("时间轴视图")
        case .overview: AppLocalization.string("表格视图")
        case .templates: AppLocalization.string("模板管理")
        }
    }

    var symbolName: String {
        switch self {
        case .dashboard: "house"
        case .timeline: "calendar.day.timeline.leading"
        case .overview: "tablecells"
        case .templates: "square.grid.2x2"
        }
    }
}
