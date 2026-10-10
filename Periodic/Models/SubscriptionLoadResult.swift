import Foundation

struct SubscriptionLoadResult: Sendable {
    let subscriptions: [SubscriptionDTO]
    let invalidRecordCount: Int
}

enum SubscriptionLoadError: LocalizedError {
    case invalidRecords(Int)

    var errorDescription: String? {
        switch self {
        case .invalidRecords(let count):
            String(format: AppLocalization.string("有 %d 条订阅无法读取，已显示其余有效记录。原始数据仍保留，请从备份恢复或检查数据后重试。"), count)
        }
    }
}
