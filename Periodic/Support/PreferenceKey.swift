import Foundation

enum PreferenceKey {
    static let appearance = "appearance"
    static let language = "language"
    static let defaultCurrency = "defaultCurrency"
    static let usesCurrencySymbols = "usesCurrencySymbols"
    static let menuBarEnabled = "menuBarEnabled"
    static let menuBarDueHorizon = "menuBarDueHorizon"
    static let menuBarShowsForecasts = "menuBarShowsForecasts"
    static let exchangeRateBaseCurrency = "exchangeRateBaseCurrency"
    static let selectedCurrencies = "selectedCurrencies"
    static let defaultTimelineRange = "defaultTimelineRange"
    static let timelineSortField = "timelineSortField"
    static let timelineSortDirection = "timelineSortDirection"
    static let timelineUpcomingExpanded = "timelineUpcomingExpanded"
    static let overviewVisibleColumns = "overviewVisibleColumns"
    static let overviewSortOption = "overviewSortOption"
    static let datasetID = "datasetID"
    static let iCloudSyncEnabled = "iCloudSyncEnabled"
    static let iCloudLastSuccessfulSyncAt = "iCloudLastSuccessfulSyncAt"
    static let iCloudLastSafetySnapshotPath = "iCloudLastSafetySnapshotPath"
    static let submittedNotificationRequests = "submittedNotificationRequests"
    static let submittedSampleNotificationRequests = "submittedSampleNotificationRequests"
    static let pendingIconCleanupReferences = "pendingIconCleanupReferences"
    static let pendingPaymentAttachmentCleanupReferences =
        "pendingPaymentAttachmentCleanupReferences"
    static let completedLifetimePeriodBackfill = "completedLifetimePeriodBackfill"

    static func lifetimePeriodBackfillCompleted(datasetID: UUID) -> String {
        completedLifetimePeriodBackfill + "." + datasetID.uuidString
    }
}
