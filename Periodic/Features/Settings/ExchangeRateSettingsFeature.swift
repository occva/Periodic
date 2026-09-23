import Foundation
import Observation

@MainActor
@Observable
final class ExchangeRateSettingsFeature {
    private(set) var catalog: ExchangeRateCatalog?
    private(set) var isLoading = false
    private(set) var error: PresentedError?
    private var generation = 0

    func load(using client: FrankfurterExchangeRateClient, baseCurrency: CurrencyCode) async {
        generation &+= 1
        let currentGeneration = generation
        isLoading = true
        error = nil

        if let cached = await client.cachedCatalog(baseCurrency: baseCurrency) {
            catalog = cached
        } else {
            catalog = nil
        }

        do {
            let loaded = try await client.latestCatalog(baseCurrency: baseCurrency)
            guard currentGeneration == generation else { return }
            catalog = loaded
        } catch {
            guard currentGeneration == generation else { return }
            self.error = PresentedError(error, title: "无法读取汇率")
        }
        guard currentGeneration == generation else { return }
        isLoading = false
    }

    func refresh(using client: FrankfurterExchangeRateClient, baseCurrency: CurrencyCode) async {
        generation &+= 1
        let currentGeneration = generation
        isLoading = true
        error = nil

        do {
            let loaded = try await client.refreshCatalog(baseCurrency: baseCurrency)
            guard currentGeneration == generation else { return }
            catalog = loaded
        } catch {
            guard currentGeneration == generation else { return }
            self.error = PresentedError(error, title: "无法刷新汇率")
        }
        guard currentGeneration == generation else { return }
        isLoading = false
    }
}
