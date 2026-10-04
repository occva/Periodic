import SwiftUI

struct TimelineView: View {
    @Bindable var session: WindowSession
    @AppStorage(PreferenceKey.timelineSortField) private var timelineSortFieldRaw =
        TimelinePreferences.defaultSortField.rawValue
    @AppStorage(PreferenceKey.timelineSortDirection) private var timelineSortDirectionRaw =
        TimelinePreferences.defaultSortDirection.rawValue
    @AppStorage(PreferenceKey.timelineUpcomingExpanded) private var isUpcomingExpanded =
        TimelinePreferences.defaultUpcomingExpanded

    @State private var centerDate = Date()
    @State private var pendingHorizontalDayOffset = 0.0
    @State private var specialCollection: TimelineSpecialCollection?

    var body: some View {
        VStack(spacing: 0) {
            TimelineGridView(
                items: sortedDatedItems,
                centerDate: centerDate,
                range: session.timelineRange,
                referenceDate: session.referenceDate,
                onEdit: session.presentEditor(for:),
                onDetails: session.presentDetails(for:),
                onCenter: { centerTimeline(on: $0.date()) },
                onHorizontalScroll: panTimeline
            )
            upcomingSection
        }
        .toolbar { toolbarContent }
        .sheet(item: $specialCollection) { collection in
            TimelineCollectionListView(
                title: collection.title,
                items: collection == .undated ? session.undatedItems : session.lifetimeItems,
                onDetails: { openFromSpecialCollection(id: $0, editing: false) },
                onEdit: { openFromSpecialCollection(id: $0, editing: true) }
            )
        }
        .accessibilityIdentifier("timeline-page")
        .onChange(of: session.timelineRange) { _, _ in
            pendingHorizontalDayOffset = 0
        }
    }

    private var upcomingSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Button {
                    withAnimation(.snappy) {
                        isUpcomingExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Label("即将到期", systemImage: "clock.badge.exclamationmark")
                            .font(.headline)
                        Text(session.upcomingItems.count, format: .number)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                        Image(systemName: isUpcomingExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(AppLocalization.string(
                    isUpcomingExpanded ? "收起即将到期" : "展开即将到期"
                ))

                Spacer(minLength: 12)

                if isUpcomingExpanded {
                    horizonPicker
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)

            if isUpcomingExpanded {
                Divider()
                Group {
                    if session.upcomingItems.isEmpty {
                        ContentUnavailableView(
                            "当前条件下无临期订阅",
                            systemImage: "checkmark.circle",
                            description: Text("未来 \(session.dueHorizon.rawValue) 天内的项目会显示在这里。")
                        )
                        .frame(maxWidth: .infinity, minHeight: 112)
                    } else {
                        ScrollView(.horizontal) {
                            GlassEffectContainer(spacing: 10) {
                                HStack(spacing: 10) {
                                    ForEach(session.upcomingItems) { item in
                                        VStack(alignment: .leading, spacing: 8) {
                                            HStack(spacing: 9) {
                                                Button {
                                                    session.presentDetails(for: item.id)
                                                } label: {
                                                    ServiceIconView(
                                                        iconResourceName: item.iconResourceName,
                                                        iconURLString: item.iconURLString,
                                                        fallbackSeed: item.name,
                                                        size: 28
                                                    )
                                                }
                                                .buttonStyle(.plain)
                                                .help("查看订阅详情")
                                                .accessibilityLabel("查看 \(item.name) 的订阅详情")

                                                Text(item.name)
                                                    .font(.headline)
                                                    .lineLimit(1)
                                                Spacer(minLength: 0)
                                            }
                                            HStack(spacing: 6) {
                                                Text(item.expiryDate)
                                                Text(item.expiryStatus(relativeTo: session.referenceDate))
                                                    .fontWeight(.medium)
                                                    .foregroundStyle(.primary)
                                            }
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .monospacedDigit()
                                        }
                                        .frame(width: 210, alignment: .leading)
                                        .padding(12)
                                        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 14))
                                        .contentShape(.rect(cornerRadius: 14))
                                        .onTapGesture(count: 2) {
                                            session.presentDetails(for: item.id)
                                        }
                                        .contextMenu {
                                            Button("订阅详情") {
                                                session.presentDetails(for: item.id)
                                            }
                                            Button("编辑订阅") {
                                                session.presentEditor(for: item.id)
                                            }
                                        }
                                    }
                                }
                            }
                            .padding(10)
                        }
                        .scrollIndicators(.hidden)
                    }
                }
            }
        }
        .overlay(alignment: .top) { Divider() }
    }

    private var horizonPicker: some View {
        HStack(spacing: 8) {
            Text("临期范围")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize()
            Picker("临期范围", selection: $session.dueHorizon) {
                ForEach(DueHorizon.allCases) { horizon in
                    Text(horizon.title).tag(horizon)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 92)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button("前一范围", systemImage: "chevron.left") { shiftRange(by: -1) }
                .labelStyle(.iconOnly)
            Button("今天") { centerTimeline(on: Date()) }
            Button("后一范围", systemImage: "chevron.right") { shiftRange(by: 1) }
                .labelStyle(.iconOnly)
        }

        ToolbarSpacer(.fixed, placement: .navigation)

        ToolbarItem(placement: .navigation) {
            Picker("时间范围", selection: $session.timelineRange) {
                ForEach(TimelineRange.allCases) { range in
                    Text(range.title).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 320)
        }

        ToolbarItem(placement: .secondaryAction) {
            Menu {
                Button("订阅提醒 \(session.reminderCenterItemCount)") {
                    session.presentReminderCenter(scope: .all)
                }
                Divider()
                Button("无日期 \(session.undatedCount)") {
                    specialCollection = .undated
                }
                .disabled(session.undatedCount == 0)
                Button("终生 \(session.lifetimeCount)") {
                    specialCollection = .lifetime
                }
                .disabled(session.lifetimeCount == 0)
            } label: {
                Label(
                    "提醒与特殊项目",
                    systemImage: "tray.full"
                )
            }
        }

        ToolbarItemGroup(placement: .primaryAction) {
            sortMenu

            Menu {
                Picker("服务类型", selection: $session.timelineCategory) {
                    Text("全部服务类型").tag(nil as ServiceCategory?)
                    ForEach(ServiceCategory.allCases) { category in
                        Text(category.title).tag(Optional(category))
                    }
                }
                Picker("管理状态", selection: $session.timelineManagementState) {
                    Text("全部管理状态").tag(nil as ManagementState?)
                    ForEach(ManagementState.allCases) { state in
                        Text(state.title).tag(Optional(state))
                    }
                }
                Picker("计费类型", selection: $session.timelineBillingKind) {
                    Text("全部计费类型").tag(nil as BillingKind?)
                    ForEach(BillingKind.allCases) { kind in
                        Text(kind.title).tag(Optional(kind))
                    }
                }
                if session.hasTimelineFilters {
                    Divider()
                    Button("清除筛选") { session.clearTimelineFilters() }
                }
            } label: {
                Label("筛选", systemImage: session.hasTimelineFilters
                    ? "line.3.horizontal.decrease.circle.fill"
                    : "line.3.horizontal.decrease.circle")
            }
            Menu {
                Button("空白新建") {
                    session.presentNewSubscription()
                }
                Button("从服务模板新建") {
                    session.presentTemplateLibrary()
                }
            } label: {
                Label("新建", systemImage: "plus")
            }

            ToolbarSearchButton(
                text: $session.searchText,
                prompt: "搜索订阅名称"
            )
        }
    }

    private var sortMenu: some View {
        Menu {
            Section("时间") {
                sortFieldButton(.expiry)
                sortFieldButton(.remainingDays)
                sortFieldButton(.periodStart)
            }
            Section("费用") {
                sortFieldButton(.amount)
                sortFieldButton(.monthlyEstimate)
                sortFieldButton(.annualEstimate)
            }
            Section("资料") {
                sortFieldButton(.name)
                sortFieldButton(.category)
                sortFieldButton(.billingCycle)
                sortFieldButton(.note)
            }
            Section("状态") {
                sortFieldButton(.expiryStatus)
                sortFieldButton(.managementState)
            }
            Divider()
            Picker("排序方向", selection: sortDirectionBinding) {
                ForEach(TimelineSortDirection.allCases) { direction in
                    Label(direction.title, systemImage: direction.symbolName)
                        .tag(direction)
                }
            }
        } label: {
            Label("排序", systemImage: "arrow.up.arrow.down.circle")
        }
        .help(String(
            format: AppLocalization.string("排序：%@ · %@"),
            timelineSortField.title,
            timelineSortDirection.title
        ))
    }

    private func sortFieldButton(_ field: TimelineSortField) -> some View {
        Button {
            timelineSortFieldRaw = field.rawValue
        } label: {
            Label(
                field.title,
                systemImage: field == timelineSortField ? "checkmark" : field.symbolName
            )
        }
    }

    private var sortedDatedItems: [SubscriptionListItem] {
        timelineSortField.sorted(
            session.datedItems,
            direction: timelineSortDirection,
            referenceDate: session.referenceDate
        )
    }

    private var timelineSortField: TimelineSortField {
        TimelinePreferences.sortField(for: timelineSortFieldRaw)
    }

    private var timelineSortDirection: TimelineSortDirection {
        TimelinePreferences.sortDirection(for: timelineSortDirectionRaw)
    }

    private var sortDirectionBinding: Binding<TimelineSortDirection> {
        Binding(
            get: { timelineSortDirection },
            set: { timelineSortDirectionRaw = $0.rawValue }
        )
    }

    private func shiftRange(by direction: Int) {
        pendingHorizontalDayOffset = 0
        centerDate = Calendar.current.date(
            byAdding: .month,
            value: session.timelineRange.rawValue * direction,
            to: centerDate
        ) ?? centerDate
    }

    private func centerTimeline(on date: Date) {
        pendingHorizontalDayOffset = 0
        centerDate = date
    }

    private func panTimeline(
        deltaX: CGFloat,
        viewportWidth: CGFloat,
        layout: TimelineAxisLayout
    ) {
        pendingHorizontalDayOffset += layout.dayOffset(
            forHorizontalScroll: deltaX,
            viewportWidth: viewportWidth
        )
        let wholeDays = Int(pendingHorizontalDayOffset.rounded(.towardZero))
        guard wholeDays != 0 else { return }
        pendingHorizontalDayOffset -= Double(wholeDays)
        centerDate = Calendar.current.date(
            byAdding: .day,
            value: wholeDays,
            to: centerDate
        ) ?? centerDate
    }

    private func openFromSpecialCollection(id: UUID, editing: Bool) {
        specialCollection = nil
        Task { @MainActor in
            await Task.yield()
            if editing {
                session.presentEditor(for: id)
            } else {
                session.presentDetails(for: id)
            }
        }
    }
}

#Preview {
    NavigationStack {
        TimelineView(session: WindowSession())
    }
    .frame(width: 1100, height: 760)
}
