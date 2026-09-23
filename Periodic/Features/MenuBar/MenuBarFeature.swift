import Foundation
import Observation

@MainActor
@Observable
final class MenuBarFeature {
    private(set) var snapshot: MenuBarSubscriptionSnapshot?
    private(set) var isLoading = false
    private(set) var loadError: PresentedError?
    private(set) var exchangeRateQuote: ExchangeRateQuote?
    private(set) var exchangeRateError: PresentedError?
    private var loadGeneration = 0

    var statusItemAccessibilityLabel: String {
        if loadError != nil, snapshot == nil {
            return AppLocalization.string("Periodic，订阅信息暂不可用")
        }
        guard let snapshot else {
            return AppLocalization.string("Periodic，正在读取订阅信息")
        }
        guard snapshot.dueTodayCount > 0 else {
            return AppLocalization.string("Periodic，今天没有到期项目")
        }
        return String(
            format: AppLocalization.string("Periodic，今天有 %d 项到期"),
            snapshot.dueTodayCount
        )
    }

    func reload(
        using services: AppServices,
        referenceDate: LocalDate = .today,
        targetCurrency: CurrencyCode = AppPreferenceValues.exchangeRateBaseCurrency,
        shouldLoadExchangeRates: Bool = true
    ) async {
        loadGeneration &+= 1
        let generation = loadGeneration
        isLoading = true

        guard let store = services.subscriptionStore else {
            guard generation == loadGeneration else { return }
            isLoading = false
            loadError = services.initializationError
                ?? PresentedError(MenuBarFeatureError.storeUnavailable, title: "无法读取菜单栏订阅")
            return
        }

        do {
            let subscriptions = try await store.fetchAll()
            guard generation == loadGeneration else { return }
            let newSnapshot = MenuBarSnapshotBuilder.makeSnapshot(
                subscriptions: subscriptions,
                referenceDate: referenceDate
            )
            snapshot = newSnapshot
            loadError = nil
            guard shouldLoadExchangeRates else {
                isLoading = false
                return
            }
            let loadedQuote: ExchangeRateQuote?
            let rateError: PresentedError?
            if newSnapshot.currencyForecasts.isEmpty {
                loadedQuote = nil
                rateError = nil
            } else if newSnapshot.currencyForecasts.allSatisfy({ $0.currency == targetCurrency }) {
                loadedQuote = ExchangeRateQuote(
                    baseCurrency: targetCurrency,
                    date: referenceDate.displayText,
                    ratesPerBaseUnit: [targetCurrency: 1],
                    isStale: false,
                    source: .identity
                )
                rateError = nil
            } else {
                do {
                    loadedQuote = try await services.exchangeRates.latestQuote(
                        baseCurrency: targetCurrency,
                        currencies: Set(newSnapshot.currencyForecasts.map(\.currency))
                    )
                    rateError = nil
                } catch {
                    loadedQuote = nil
                    rateError = PresentedError(error, title: "无法更新汇率")
                }
            }
            guard generation == loadGeneration else { return }
            exchangeRateQuote = loadedQuote
            exchangeRateError = rateError
            isLoading = false
        } catch {
            guard generation == loadGeneration else { return }
            loadError = PresentedError(error, title: "无法更新菜单栏订阅")
            isLoading = false
        }
    }
}

private enum MenuBarFeatureError: LocalizedError {
    case storeUnavailable

    var errorDescription: String? { "订阅数据库尚未就绪。" }
}
