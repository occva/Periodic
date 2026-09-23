import Foundation

enum MenuBarPreferences {
    static let defaultDueHorizon = DueHorizon.fifteenDays

    static func dueHorizon(for rawValue: Int) -> DueHorizon {
        DueHorizon(rawValue: rawValue) ?? defaultDueHorizon
    }

    static func normalizedDueHorizonRawValue(_ rawValue: Int) -> Int {
        dueHorizon(for: rawValue).rawValue
    }
}
