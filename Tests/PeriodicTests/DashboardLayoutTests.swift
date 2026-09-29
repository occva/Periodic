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

    @Test func unevenItemsFlowIntoTheCurrentlyShortestColumn() {
        let layout = IndependentColumnLayout(minimumColumnWidth: 220, spacing: 12)

        let assignments = layout.columnAssignments(
            itemHeights: [100, 70, 50, 40, 30, 20],
            columnCount: 3
        )

        #expect(assignments == [0, 1, 2, 2, 1, 0])
    }

    @Test func equalHeightColumnsPreferStableLeadingOrder() {
        let layout = IndependentColumnLayout(minimumColumnWidth: 220, spacing: 12)

        let assignments = layout.columnAssignments(
            itemHeights: [40, 40, 40, 40],
            columnCount: 3
        )

        #expect(assignments == [0, 1, 2, 0])
    }
}
