import CoreGraphics
import Testing
@testable import Periodic

struct DashboardLayoutTests {
    @Test func nonFiniteProposalsUseStableFallbackWidth() {
        let layout = IndependentColumnLayout(minimumColumnWidth: 220, spacing: 12)
        let expectedWidth = CGFloat(684)

        #expect(layout.resolvedWidth(nil, itemCount: 21) == expectedWidth)
        #expect(layout.resolvedWidth(.infinity, itemCount: 21) == expectedWidth)
        #expect(layout.resolvedWidth(-.infinity, itemCount: 21) == expectedWidth)
        #expect(layout.resolvedWidth(.nan, itemCount: 21) == expectedWidth)
    }

    @Test func metricsNeverConvertNonFiniteWidthsToColumnCounts() {
        let layout = IndependentColumnLayout(minimumColumnWidth: 220, spacing: 12)

        for width in [CGFloat.infinity, -.infinity, .nan] {
            let metrics = layout.metrics(availableWidth: width, itemCount: 21)
            #expect(metrics.columnCount == 1)
            #expect(metrics.columnWidth == 220)
            #expect(metrics.columnWidth.isFinite)
        }
    }
}
