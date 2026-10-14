import Foundation

enum DashboardMetricScope: String, Identifiable, Sendable {
    case effective
    case expired

    var id: String { rawValue }
}
