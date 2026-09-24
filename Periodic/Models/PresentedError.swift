import Foundation

struct PresentedError: Identifiable {
    let id = UUID()
    let title: String
    let message: String

    init(_ error: any Error, title: String = "操作未完成") {
        self.title = AppLocalization.string(title)
        message = error.localizedDescription
    }
}
