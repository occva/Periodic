import Foundation

enum AppDestination: String, CaseIterable, Identifiable {
    case workspace

    var id: String { rawValue }
    var title: String {
        switch self {
        case .workspace: "工作区"
        }
    }

    var symbolName: String {
        switch self {
        case .workspace: "square.grid.2x2"
        }
    }
}
