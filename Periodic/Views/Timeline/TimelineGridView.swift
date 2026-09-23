import SwiftUI

struct TimelineGridView: View {
    let items: [SubscriptionListItem]
    let centerDate: Date
    let range: TimelineRange
    let onEdit: (UUID) -> Void
    let onDetails: (UUID) -> Void
    let onCenter: (LocalDate) -> Void

    private let axisHeight: CGFloat = 58
    private let rowHeight: CGFloat = 34

    var body: some View {
        GeometryReader { proxy in
            let canvasWidth = max(proxy.size.width, 1)
            let layout = TimelineAxisLayout(centerDate: centerDate, range: range)
            VStack(spacing: 0) {
                axis(layout: layout, width: canvasWidth)
                    .frame(height: axisHeight)

                ZStack {
                    grid(layout: layout, width: canvasWidth)

                    if items.isEmpty {
                        ContentUnavailableView("没有到期项目", systemImage: "calendar")
                    } else {
                        ScrollView(.vertical) {
                            GlassEffectContainer(spacing: 4) {
                                LazyVStack(spacing: 0) {
                                    ForEach(items) { item in
                                        TimelineRowView(
                                            item: item,
                                            layout: layout,
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
                }
                .frame(height: max(0, proxy.size.height - axisHeight))
            }
            .frame(width: canvasWidth)
        }
        .frame(minHeight: 300)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("timeline-grid")
    }

    private func axis(layout: TimelineAxisLayout, width: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(layout.majorTicks, id: \.dayNumber) { tick in
                Text(layout.majorLabel(for: tick))
                    .font(.caption.weight(.semibold))
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
                        .position(x: layout.x(for: tick, width: width), y: 39)
                }
            }

            if layout.contains(.today) {
                Circle()
                    .fill(.red)
                    .frame(width: 24, height: 24)
                    .position(x: layout.x(for: .today, width: width), y: 39)
                Text(layout.todayLabel(for: .today))
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
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
                    .fill(.separator.opacity(0.22))
                    .frame(width: 1)
                    .offset(x: layout.x(for: tick, width: width))
            }

            ForEach(layout.majorTicks, id: \.dayNumber) { tick in
                Rectangle()
                    .fill(.separator.opacity(0.58))
                    .frame(width: 1)
                    .offset(x: layout.x(for: tick, width: width))
            }

            if layout.contains(.today) {
                Rectangle()
                    .fill(.red.opacity(0.72))
                    .frame(width: 1)
                    .offset(x: layout.x(for: .today, width: width))
            }
        }
    }
}

private struct TimelineRowView: View {
    let item: SubscriptionListItem
    let layout: TimelineAxisLayout
    let onEdit: (UUID) -> Void
    let onDetails: (UUID) -> Void
    let onCenter: (LocalDate) -> Void

    private var markerColor: Color {
        if item.managementState == .inactive { return .secondary }
        if (item.remainingDayCount ?? 0) < 0 { return .red }
        return .accentColor
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let rowCenterY = proxy.size.height / 2
            let rawX = layout.x(for: item.expiry ?? .today, width: width)
            let badgeMaximumWidth: CGFloat = 220
            let badgeCenterX = min(
                max(rawX + badgeMaximumWidth / 2 + 8, badgeMaximumWidth / 2),
                width - badgeMaximumWidth / 2
            )

            ZStack(alignment: .leading) {
                Divider().frame(maxHeight: .infinity, alignment: .bottom)

                if rawX < 0 {
                    Button {
                        if let expiry = item.expiry { onCenter(expiry) }
                    } label: {
                        Label(item.name, systemImage: "chevron.left")
                    }
                        .buttonStyle(.plain)
                        .lineLimit(1)
                        .padding(.leading, 8)
                } else if rawX > width {
                    Button {
                        if let expiry = item.expiry { onCenter(expiry) }
                    } label: {
                        Label(item.name, systemImage: "chevron.right")
                    }
                        .buttonStyle(.plain)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.trailing, 8)
                } else {
                    Rectangle()
                        .fill(markerColor)
                        .frame(width: 2, height: 22)
                        .position(x: rawX, y: rowCenterY)

                    HStack(spacing: 4) {
                        Button {
                            onDetails(item.id)
                        } label: {
                            ServiceIconView(
                                iconResourceName: item.iconResourceName,
                                iconURLString: item.iconURLString,
                                fallbackSeed: item.name,
                                size: 16
                            )
                        }
                        .buttonStyle(.plain)
                        .help("查看订阅详情")
                        .accessibilityLabel("查看 \(item.name) 的订阅详情")
                        Text(item.name)
                            .lineLimit(1)
                            .layoutPriority(1)
                        Text(item.remainingDays)
                            .monospacedDigit()
                            .frame(minWidth: 18, alignment: .trailing)
                        ProgressView(value: item.remainingProgress(relativeTo: .today) ?? 0)
                            .progressViewStyle(.linear)
                            .tint(markerColor)
                            .frame(width: 44)
                        Text(item.expiryStatus)
                            .foregroundStyle(.secondary)
                            .fixedSize()
                    }
                    .font(.caption)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 3)
                    .glassEffect(.regular.interactive(), in: .capsule)
                    .frame(width: badgeMaximumWidth, alignment: .leading)
                    .position(x: badgeCenterX, y: rowCenterY)
                }
            }
        }
        .opacity(item.managementState == .active ? 1 : 0.55)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onDetails(item.id) }
        .contextMenu {
            Button("订阅详情") { onDetails(item.id) }
            Button("编辑订阅") { onEdit(item.id) }
        }
        .accessibilityLabel("\(item.name)，到期日期 \(item.expiryDate)，\(item.expiryStatus)，\(item.managementStatus)")
    }
}
