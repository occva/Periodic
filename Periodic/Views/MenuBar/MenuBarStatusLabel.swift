import AppKit
import SwiftUI

struct MenuBarStatusLabel: View {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(PreferenceKey.exchangeRateBaseCurrency) private var baseCurrency = CurrencyCode.cny
    @AppStorage(PreferenceKey.menuBarShowsForecasts) private var showsForecasts = true

    let feature: MenuBarFeature
    let services: AppServices

    private let icon = MenuBarApplicationIcon.makeImage()

    var body: some View {
        HStack(spacing: 3) {
            Image(nsImage: icon)
            if let count = feature.snapshot?.dueTodayCount, count > 0 {
                Text(count > 99 ? "99+" : "\(count)")
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(feature.statusItemAccessibilityLabel)
        .help(feature.statusItemAccessibilityLabel)
        .task {
            await feature.reload(
                using: services,
                targetCurrency: baseCurrency,
                shouldLoadExchangeRates: showsForecasts
            )
        }
        .onChange(of: services.subscriptionDataVersion) { _, _ in
            reload()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                reload()
            }
        }
        .onChange(of: baseCurrency) { _, _ in
            reload()
        }
        .onChange(of: showsForecasts) { _, _ in
            reload()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            reload()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemClockDidChange)) { _ in
            reload()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
            reload()
        }
    }

    private func reload() {
        Task { @MainActor in
            await feature.reload(
                using: services,
                targetCurrency: baseCurrency,
                shouldLoadExchangeRates: showsForecasts
            )
        }
    }
}

@MainActor
private enum MenuBarApplicationIcon {
    static func makeImage() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let source = NSApplication.shared.applicationIconImage
            ?? NSImage(systemSymbolName: "cat.fill", accessibilityDescription: nil)
            ?? NSImage(size: size)
        let image = NSImage(size: size, flipped: false) { destinationRect in
            source.draw(
                in: destinationRect,
                from: .zero,
                operation: .sourceOver,
                fraction: 1
            )
            return true
        }
        image.size = size
        return image
    }
}
