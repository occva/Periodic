import Foundation
import Observation

@MainActor
@Observable
final class WindowSession {
    var searchText = ""
    var quickView = SubscriptionQuickView.all
    var grouping = OverviewGrouping.none
    var overviewManagementState: ManagementState?
    var overviewExpiryFilter = OverviewExpiryFilter.all
    var overviewCategory: ServiceCategory?
    var overviewBillingKind: BillingKind?
    var overviewCurrency: CurrencyCode?
    var timelineRange: TimelineRange
    var dueHorizon = DueHorizon.fifteenDays
    var timelineCategory: ServiceCategory?
    var timelineManagementState: ManagementState?
    var timelineBillingKind: BillingKind?
    private(set) var referenceDate: LocalDate
    private(set) var exchangeRateRefreshRevision = 0
    private(set) var isPresentingSubscriptionEditor = false
    private(set) var isPresentingSubscriptionDetail = false
    private(set) var isPresentingTemplateLibrary = false
    private(set) var editingSubscriptionID: UUID?
    private(set) var subscriptionEditorPreset: SubscriptionTemplatePreset?
    private(set) var detailSubscriptionID: UUID?
    private(set) var subscriptions: [SubscriptionDTO] = []
    private(set) var items: [SubscriptionListItem] = []
    private(set) var isLoading = false
    private(set) var hasLoadedSubscriptions = false
    var loadError: PresentedError?

    init(
        referenceDate: LocalDate = .today,
        timelineRange: TimelineRange = TimelinePreferences.defaultRange
    ) {
        self.referenceDate = referenceDate
        self.timelineRange = timelineRange
    }

    var analytics: SubscriptionAnalytics {
        SubscriptionAnalytics(items: items, referenceDate: referenceDate)
    }

    var filteredItems: [SubscriptionListItem] {
        items
            .filter(matchesSearch)
            .filter(matchesQuickView)
            .filter(matchesOverviewFilters)
            .sorted(by: remainingDaysDescending)
    }

    var datedItems: [SubscriptionListItem] {
        timelineItems.filter { $0.billingKindValue == .recurring && $0.expiry != nil }
    }

    var undatedCount: Int {
        undatedItems.count
    }

    var lifetimeCount: Int {
        lifetimeItems.count
    }

    var undatedItems: [SubscriptionListItem] {
        timelineItems.filter { $0.billingKindValue == .recurring && $0.expiry == nil }
    }

    var lifetimeItems: [SubscriptionListItem] {
        timelineItems.filter { $0.billingKindValue == .lifetime }
    }

    var upcomingItems: [SubscriptionListItem] {
        timelineItems.filter(isUpcoming)
    }

    var hasTimelineFilters: Bool {
        timelineCategory != nil || timelineManagementState != nil || timelineBillingKind != nil
    }

    var hasOverviewFilters: Bool {
        overviewManagementState != nil
            || overviewExpiryFilter != .all
            || overviewCategory != nil
            || overviewBillingKind != nil
            || overviewCurrency != nil
    }

    var dashboardUpcomingItems: [SubscriptionListItem] {
        analytics.upcomingItems(within: dueHorizon.rawValue)
    }

    var dashboardActiveSubscriptionItems: [SubscriptionListItem] {
        items
            .filter { analytics.status(of: $0) == .effectiveRecurring }
            .sorted(by: expiryAscending)
    }

    var automaticRenewalDueItems: [SubscriptionListItem] {
        items.filter { item in
            guard item.managementState == .active,
                  item.billingKindValue == .recurring,
                  item.automaticallyRenews,
                  let expiry = item.expiry,
                  let cycleMonths = item.cycleMonths else {
                return false
            }
            return cycleMonths > 0 && expiry <= referenceDate
        }
        .sorted(by: expiryAscending)
    }

    var editingSubscription: SubscriptionDTO? {
        guard let editingSubscriptionID else { return nil }
        return subscriptions.first { $0.id == editingSubscriptionID }
    }

    var detailSubscription: SubscriptionDTO? {
        guard let detailSubscriptionID else { return nil }
        return subscriptions.first { $0.id == detailSubscriptionID }
    }

    func presentNewSubscription(preset: SubscriptionTemplatePreset? = nil) {
        editingSubscriptionID = nil
        subscriptionEditorPreset = preset
        isPresentingSubscriptionEditor = true
    }

    func presentTemplateLibrary() {
        dismissEditor()
        isPresentingTemplateLibrary = true
    }

    func dismissTemplateLibrary() {
        isPresentingTemplateLibrary = false
    }

    func presentEditor(for id: UUID) {
        guard subscriptions.contains(where: { $0.id == id }) else { return }
        subscriptionEditorPreset = nil
        editingSubscriptionID = id
        isPresentingSubscriptionEditor = true
    }

    func presentDetails(for id: UUID) {
        _ = tryPresentDetails(for: id)
    }

    @discardableResult
    func tryPresentDetails(for id: UUID) -> Bool {
        guard subscriptions.contains(where: { $0.id == id }) else { return false }
        detailSubscriptionID = id
        isPresentingSubscriptionDetail = true
        return true
    }

    func dismissDetails() {
        isPresentingSubscriptionDetail = false
        detailSubscriptionID = nil
    }

    func dismissEditor() {
        isPresentingSubscriptionEditor = false
        editingSubscriptionID = nil
        subscriptionEditorPreset = nil
    }

    func clearTimelineFilters() {
        timelineCategory = nil
        timelineManagementState = nil
        timelineBillingKind = nil
    }

    func clearOverviewFilters() {
        overviewManagementState = nil
        overviewExpiryFilter = .all
        overviewCategory = nil
        overviewBillingKind = nil
        overviewCurrency = nil
    }

    func reload(using services: AppServices) async {
        referenceDate = .today
        exchangeRateRefreshRevision &+= 1
        guard let store = services.subscriptionStore else {
            loadError = services.initializationError
            hasLoadedSubscriptions = true
            return
        }

        isLoading = true
        defer { isLoading = false }
        do {
            subscriptions = try await store.fetchAll()
            items = subscriptions.map(SubscriptionListItem.init(dto:))
            await services.reconcileRenewalNotifications(
                subscriptions: subscriptions,
                referenceDate: referenceDate
            )
            loadError = nil
        } catch {
            loadError = PresentedError(error, title: "无法读取订阅")
        }
        hasLoadedSubscriptions = true
    }

    private func matchesSearch(_ item: SubscriptionListItem) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty || item.name.localizedCaseInsensitiveContains(query)
    }

    private var timelineItems: [SubscriptionListItem] {
        items
            .filter(matchesSearch)
            .filter { timelineCategory == nil || $0.categoryValue == timelineCategory }
            .filter { timelineManagementState == nil || $0.managementState == timelineManagementState }
            .filter { timelineBillingKind == nil || $0.billingKindValue == timelineBillingKind }
            .sorted(by: expiryAscending)
    }

    private func isUpcoming(_ item: SubscriptionListItem) -> Bool {
        guard item.managementState == .active,
              item.billingKindValue == .recurring,
              let days = item.remainingDayCount(relativeTo: referenceDate) else { return false }
        return (0...dueHorizon.rawValue).contains(days)
    }

    private func matchesQuickView(_ item: SubscriptionListItem) -> Bool {
        switch quickView {
        case .all:
            return true
        case .active:
            let status = analytics.status(of: item)
            return status != .inactive && status != .expired
        case .expired:
            return analytics.status(of: item) == .expired
        case .inactive:
            return item.managementState == .inactive
        case .lifetime:
            return item.billingKindValue == .lifetime
        }
    }

    private func matchesOverviewFilters(_ item: SubscriptionListItem) -> Bool {
        guard overviewManagementState == nil || item.managementState == overviewManagementState,
              overviewCategory == nil || item.categoryValue == overviewCategory,
              overviewBillingKind == nil || item.billingKindValue == overviewBillingKind,
              overviewCurrency == nil || item.money.currency == overviewCurrency else {
            return false
        }

        return switch overviewExpiryFilter {
        case .all:
            true
        case .effective:
            analytics.status(of: item) == .effectiveRecurring
        case .expired:
            analytics.status(of: item) == .expired
        case .unknownDate:
            analytics.status(of: item) == .unknownDate
        case .lifetime:
            analytics.status(of: item) == .effectiveLifetime
        }
    }

    private func expiryAscending(_ lhs: SubscriptionListItem, _ rhs: SubscriptionListItem) -> Bool {
        switch (lhs.expiry, rhs.expiry) {
        case let (left?, right?):
            if left != right { return left < right }
            if lhs.name != rhs.name { return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending }
            return lhs.id.uuidString < rhs.id.uuidString
        case (_?, nil): return true
        case (nil, _?): return false
        case (nil, nil):
            if lhs.name != rhs.name { return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private func remainingDaysDescending(
        _ lhs: SubscriptionListItem,
        _ rhs: SubscriptionListItem
    ) -> Bool {
        let left = lhs.remainingDayCount(relativeTo: referenceDate)
        let right = rhs.remainingDayCount(relativeTo: referenceDate)

        switch (left, right) {
        case let (left?, right?):
            if left != right { return left > right }
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        case (nil, nil):
            break
        }

        if lhs.name != rhs.name {
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
