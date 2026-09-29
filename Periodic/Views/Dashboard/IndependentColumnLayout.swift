import SwiftUI

/// Places each item in the currently shortest column so uneven disclosure
/// content stays visually balanced without splitting an item across columns.
struct IndependentColumnLayout: Layout {
    let minimumColumnWidth: CGFloat
    let spacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let availableWidth = resolvedWidth(
            proposal.width,
            itemCount: subviews.count
        )
        let metrics = metrics(availableWidth: availableWidth, itemCount: subviews.count)
        let itemHeights = subviews.map { subview in
            subview.sizeThatFits(
                ProposedViewSize(width: metrics.columnWidth, height: nil)
            ).height
        }
        let columnHeights = resolvedColumnHeights(
            itemHeights: itemHeights,
            columnCount: metrics.columnCount
        )

        return CGSize(width: availableWidth, height: columnHeights.max() ?? 0)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let metrics = metrics(availableWidth: bounds.width, itemCount: subviews.count)
        let itemProposal = ProposedViewSize(width: metrics.columnWidth, height: nil)
        let itemSizes = subviews.map { $0.sizeThatFits(itemProposal) }
        let assignments = columnAssignments(
            itemHeights: itemSizes.map(\.height),
            columnCount: metrics.columnCount
        )
        var columnOffsets = Array(repeating: CGFloat.zero, count: metrics.columnCount)

        for (index, subview) in subviews.enumerated() {
            let column = assignments[index]
            if columnOffsets[column] > 0 {
                columnOffsets[column] += spacing
            }
            let point = CGPoint(
                x: bounds.minX + CGFloat(column) * (metrics.columnWidth + spacing),
                y: bounds.minY + columnOffsets[column]
            )
            subview.place(at: point, anchor: .topLeading, proposal: itemProposal)
            columnOffsets[column] += normalizedHeight(itemSizes[index].height)
        }
    }

    func columnAssignments(itemHeights: [CGFloat], columnCount: Int) -> [Int] {
        guard columnCount > 0 else { return [] }
        var columnHeights = Array(repeating: CGFloat.zero, count: columnCount)

        return itemHeights.map { itemHeight in
            let column = shortestColumn(in: columnHeights)
            if columnHeights[column] > 0 {
                columnHeights[column] += spacing
            }
            columnHeights[column] += normalizedHeight(itemHeight)
            return column
        }
    }

    func metrics(availableWidth: CGFloat, itemCount: Int) -> Metrics {
        let normalizedWidth = availableWidth.isFinite && availableWidth > 0
            ? availableWidth
            : minimumColumnWidth
        let maximumColumnCount = max(itemCount, 1)
        let fittingColumnCount = Int(
            min(
                CGFloat(maximumColumnCount),
                max(1, (normalizedWidth + spacing) / (minimumColumnWidth + spacing))
            )
        )
        let columnCount = min(maximumColumnCount, fittingColumnCount)
        let totalSpacing = spacing * CGFloat(columnCount - 1)
        return Metrics(
            columnCount: columnCount,
            columnWidth: max(0, (normalizedWidth - totalSpacing) / CGFloat(columnCount))
        )
    }

    func resolvedWidth(_ proposedWidth: CGFloat?, itemCount: Int) -> CGFloat {
        if let proposedWidth, proposedWidth.isFinite, proposedWidth > 0 {
            return proposedWidth
        }
        let fallbackColumnCount = min(max(itemCount, 1), 3)
        return minimumColumnWidth * CGFloat(fallbackColumnCount)
            + spacing * CGFloat(fallbackColumnCount - 1)
    }

    private func resolvedColumnHeights(
        itemHeights: [CGFloat],
        columnCount: Int
    ) -> [CGFloat] {
        let assignments = columnAssignments(
            itemHeights: itemHeights,
            columnCount: columnCount
        )
        var columnHeights = Array(repeating: CGFloat.zero, count: columnCount)

        for (itemHeight, column) in zip(itemHeights, assignments) {
            if columnHeights[column] > 0 {
                columnHeights[column] += spacing
            }
            columnHeights[column] += normalizedHeight(itemHeight)
        }
        return columnHeights
    }

    private func shortestColumn(in columnHeights: [CGFloat]) -> Int {
        var shortestColumn = 0
        for column in columnHeights.indices.dropFirst()
        where columnHeights[column] < columnHeights[shortestColumn] {
            shortestColumn = column
        }
        return shortestColumn
    }

    private func normalizedHeight(_ height: CGFloat) -> CGFloat {
        height.isFinite && height > 0 ? height : 0
    }

    struct Metrics: Equatable {
        let columnCount: Int
        let columnWidth: CGFloat
    }
}
