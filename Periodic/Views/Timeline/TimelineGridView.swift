import SwiftUI

struct TimelineGridView: View {
    let items: [SubscriptionListItem]
    let centerDate: Date
    let range: TimelineRange
    let referenceDate: LocalDate
    let onEdit: (UUID) -> Void
    let onDetails: (UUID) -> Void
    let onCenter: (LocalDate) -> Void
    let onHorizontalScroll: (CGFloat, CGFloat, TimelineAxisLayout) -> Void

    private let axisHeight: CGFloat = 58
    private let rowHeight: CGFloat = 38

    var body: some View {
        GeometryReader { proxy in
            let canvasWidth = max(proxy.size.width, 1)
            let layout = TimelineAxisLayout(centerDate: centerDate, range: range)
            VStack(spacing: 0) {
                axis(layout: layout, width: canvasWidth)
                    .frame(height: axisHeight)

                ZStack {
                    grid(layout: layout, width: canvasWidth)
                        .frame(width: canvasWidth, alignment: .leading)
                        .frame(maxHeight: .infinity, alignment: .topLeading)

                    if items.isEmpty {
                        ContentUnavailableView("没有到期项目", systemImage: "calendar")
                    } else {
                        ScrollView(.vertical) {
                            LazyVStack(spacing: 0) {
                                ForEach(items) { item in
                                    TimelineRowView(
                                        item: item,
                                        layout: layout,
                                        referenceDate: referenceDate,
                                        onEdit: onEdit,
                                        onDetails: onDetails,
                                        onCenter: onCenter
                                    )
                                    .frame(height: rowHeight)
                                }
                            }
                        }
                    }
                }
                .frame(height: max(0, proxy.size.height - axisHeight))
            }
            .frame(width: canvasWidth)
            .background {
                HorizontalScrollEventView { deltaX, viewportWidth in
                    onHorizontalScroll(deltaX, viewportWidth, layout)
                }
            }
        }
        .frame(minHeight: 300)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("timeline-grid")
    }

    private func axis(layout: TimelineAxisLayout, width: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(layout.majorTicks, id: \.dayNumber) { tick in
                Text(layout.majorLabel(for: tick))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.primary)
                    .position(x: layout.majorLabelX(for: tick, width: width), y: 14)
            }

            ForEach(Array(layout.minorTicks.enumerated()), id: \.element.dayNumber) { index, tick in
                if tick != .today && shouldShowMinorLabel(
                    at: index,
                    minorTickCount: layout.minorTicks.count,
                    width: width
                ) {
                    Text(layout.minorLabel(for: tick))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .position(x: layout.x(for: tick, width: width), y: 39)
                }
            }

            if layout.contains(.today) {
                Circle()
                    .fill(.red)
                    .frame(width: 28, height: 28)
                    .shadow(color: .red.opacity(0.18), radius: 5)
                    .position(x: layout.x(for: .today, width: width), y: 39)
                Text(layout.todayLabel(for: .today))
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    .position(x: layout.x(for: .today, width: width), y: 39)
            }

            Divider().offset(y: axisHeight - 1)
        }
    }

    private func shouldShowMinorLabel(
        at index: Int,
        minorTickCount: Int,
        width: CGFloat
    ) -> Bool {
        let intervalCount = max(minorTickCount - 1, 1)
        let availableSpacing = width / CGFloat(intervalCount)
        let minimumLabelSpacing: CGFloat = switch range {
        case .oneMonth: 22
        case .threeMonths, .sixMonths, .oneYear: 28
        case .threeYears, .fiveYears: 22
        }
        let stride = max(1, Int(ceil(minimumLabelSpacing / max(availableSpacing, 1))))
        return index.isMultiple(of: stride)
    }

    private func grid(layout: TimelineAxisLayout, width: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(layout.minorTicks, id: \.dayNumber) { tick in
                Rectangle()
                    .fill(.separator.opacity(0.16))
                    .frame(width: 1)
                    .offset(x: layout.x(for: tick, width: width))
            }

            ForEach(layout.majorTicks, id: \.dayNumber) { tick in
                Rectangle()
                    .fill(.separator.opacity(0.44))
                    .frame(width: 1)
                    .offset(x: layout.x(for: tick, width: width))
            }

            if layout.contains(.today) {
                Rectangle()
                    .fill(.red.opacity(0.68))
                    .frame(width: 1.5)
                    .offset(x: layout.x(for: .today, width: width))
            }
        }
    }
}

private struct TimelineRowView: View {
    let item: SubscriptionListItem
    let layout: TimelineAxisLayout
    let referenceDate: LocalDate
    let onEdit: (UUID) -> Void
    let onDetails: (UUID) -> Void
    let onCenter: (LocalDate) -> Void

    private var statusColor: Color {
        if item.managementState == .inactive { return .secondary }
        guard let days = item.remainingDayCount(relativeTo: referenceDate) else {
            return .secondary
        }
        if days < 0 { return .secondary }
        if days == 0 { return .orange }
        return .green
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let rowCenterY = proxy.size.height / 2
            let rawX = layout.x(for: item.expiry ?? .today, width: width)
            let anchorWidth: CGFloat = 24
            let minimumEventWidth: CGFloat = 150
            let maximumEventWidth: CGFloat = 310
            let rightSpace = max(anchorWidth, width - rawX + anchorWidth / 2 - 8)
            let leftSpace = max(anchorWidth, rawX + anchorWidth / 2 - 8)
            let direction: HorizontalEdge = rightSpace >= minimumEventWidth
                || rightSpace >= leftSpace ? .trailing : .leading
            let availableWidth = direction == .trailing ? rightSpace : leftSpace
            let eventWidth = min(maximumEventWidth, max(anchorWidth, availableWidth))
            let eventCenterX = direction == .trailing
                ? rawX + (eventWidth - anchorWidth) / 2
                : rawX - (eventWidth - anchorWidth) / 2

            ZStack(alignment: .leading) {
                if rawX < 0 {
                    edgeIndicator(direction: .leading)
                } else if rawX > width {
                    edgeIndicator(direction: .trailing)
                } else {
                    TimelineEventLabel(
                        item: item,
                        referenceDate: referenceDate,
                        statusColor: statusColor,
                        direction: direction,
                        onDetails: onDetails
                    )
                    .frame(width: eventWidth)
                    .position(x: eventCenterX, y: rowCenterY)
                }
            }
        }
        .opacity(item.managementState == .active ? 1 : 0.5)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onDetails(item.id) }
        .contextMenu {
            Button("订阅详情") { onDetails(item.id) }
            Button("编辑订阅") { onEdit(item.id) }
        }
        .accessibilityLabel(
            "\(item.name)，到期日期 \(item.expiryDate)，"
                + "\(item.expiryStatus(relativeTo: referenceDate))，"
                + "\(item.managementStatus(relativeTo: referenceDate))"
        )
    }

    @ViewBuilder
    private func edgeIndicator(direction: HorizontalEdge) -> some View {
        Button {
            if let expiry = item.expiry { onCenter(expiry) }
        } label: {
            HStack(spacing: 7) {
                if direction == .leading {
                    edgeArrow("chevron.left")
                }
                Text(item.name)
                    .lineLimit(1)
                if direction == .trailing {
                    edgeArrow("chevron.right")
                }
            }
            .font(.caption.weight(.medium))
        }
        .buttonStyle(.plain)
        .frame(
            maxWidth: .infinity,
            alignment: direction == .leading ? .leading : .trailing
        )
        .padding(.horizontal, 8)
        .help(direction == .leading ? "定位到更早的到期日" : "定位到更晚的到期日")
    }

    private func edgeArrow(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .frame(width: 20, height: 20)
            .background(.secondary, in: .rect(cornerRadius: 5))
    }
}

private struct TimelineEventLabel: View {
    let item: SubscriptionListItem
    let referenceDate: LocalDate
    let statusColor: Color
    let direction: HorizontalEdge
    let onDetails: (UUID) -> Void

    private var remainingDays: Int? {
        item.remainingDayCount(relativeTo: referenceDate)
    }

    var body: some View {
        Button {
            onDetails(item.id)
        } label: {
            HStack(spacing: 5) {
                if direction == .trailing {
                    anchor
                }
                eventDetails
                if direction == .leading {
                    anchor
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("打开 \(item.name) 详情")
    }

    private var anchor: some View {
        HStack(spacing: 3) {
            if direction == .trailing {
                statusBar
            }
            ServiceIconView(
                iconResourceName: item.iconResourceName,
                iconURLString: item.iconURLString,
                fallbackSeed: item.name,
                size: 18
            )
            if direction == .leading {
                statusBar
            }
        }
        .frame(width: 24)
    }

    private var statusBar: some View {
        Capsule()
            .fill(statusColor)
            .frame(width: 2, height: 14)
    }

    private var eventDetails: some View {
        HStack(spacing: 8) {
            if direction == .leading {
                statusDetails
                Spacer(minLength: 0)
            }

            Text(item.name)
                .font(.callout.weight(.semibold))
                .lineLimit(1)
                .layoutPriority(2)

            if let remainingDays {
                Text(remainingDays, format: .number)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.primary)
                    .fixedSize()

                ProgressView(
                    value: item.remainingDaysProgress(relativeTo: referenceDate) ?? 0
                )
                .progressViewStyle(.linear)
                .tint(statusColor)
                .frame(width: 40)
                .help("按 100 天刻度显示剩余时间")

                if direction == .trailing {
                    statusDetails
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: direction == .trailing ? .leading : .trailing)
    }

    @ViewBuilder
    private var statusDetails: some View {
        if let remainingDays, remainingDays <= 0 {
            Text(item.expiryStatus(relativeTo: referenceDate))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize()
        }
    }
}
