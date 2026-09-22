import SwiftUI

/// Unlike `LazyVGrid`, each column measures its own height so expanding a
/// disclosure only moves the cards below it in the same column.
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
        var columnHeights = Array(repeating: CGFloat.zero, count: metrics.columnCount)

        for (index, subview) in subviews.enumerated() {
            let column = index % metrics.columnCount
            let size = subview.sizeThatFits(
                ProposedViewSize(width: metrics.columnWidth, height: nil)
            )
            if columnHeights[column] > 0 {
                columnHeights[column] += spacing
            }
            columnHeights[column] += size.height
        }

        return CGSize(width: availableWidth, height: columnHeights.max() ?? 0)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let metrics = metrics(availableWidth: bounds.width, itemCount: subviews.count)
        var columnOffsets = Array(repeating: CGFloat.zero, count: metrics.columnCount)

        for (index, subview) in subviews.enumerated() {
            let column = index % metrics.columnCount
            if columnOffsets[column] > 0 {
                columnOffsets[column] += spacing
            }
            let point = CGPoint(
                x: bounds.minX + CGFloat(column) * (metrics.columnWidth + spacing),
                y: bounds.minY + columnOffsets[column]
            )
            let itemProposal = ProposedViewSize(width: metrics.columnWidth, height: nil)
            subview.place(at: point, anchor: .topLeading, proposal: itemProposal)
            columnOffsets[column] += subview.sizeThatFits(itemProposal).height
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

    struct Metrics: Equatable {
        let columnCount: Int
        let columnWidth: CGFloat
    }
}
