import SwiftUI

struct TimelineView: View {
    @Bindable var session: WindowSession
    @State private var centerDate = Date()
    @State private var isUpcomingExpanded = true
    @State private var specialCollection: TimelineSpecialCollection?

    var body: some View {
        VStack(spacing: 0) {
            timelineControls
            Divider()
            TimelineGridView(
                items: session.datedItems,
                centerDate: centerDate,
                range: session.timelineRange,
                onEdit: session.presentEditor(for:),
                onDetails: session.presentDetails(for:),
                onCenter: { centerDate = $0.date() }
            )
            Divider()
            upcomingSection
        }
        .searchable(text: $session.searchText, placement: .toolbar, prompt: "搜索订阅名称")
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
    }

    private var timelineControls: some View {
        HStack(spacing: 8) {
            Button("前一范围", systemImage: "chevron.left") { shiftRange(by: -1) }
                .labelStyle(.iconOnly)
            Button("今天") { centerDate = Date() }
            Button("后一范围", systemImage: "chevron.right") { shiftRange(by: 1) }
                .labelStyle(.iconOnly)

            Text("时间范围")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize()
            Picker("时间范围", selection: $session.timelineRange) {
                ForEach(TimelineRange.allCases) { range in
                    Text(range.title).tag(range)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 390)

            Spacer(minLength: 12)
            Button("无日期 \(session.undatedCount)") {
                specialCollection = .undated
            }
                .disabled(session.undatedCount == 0)
            Button("终生 \(session.lifetimeCount)") {
                specialCollection = .lifetime
            }
                .disabled(session.lifetimeCount == 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var upcomingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    upcomingTitle
                    Spacer(minLength: 12)
                    if isUpcomingExpanded { horizonPicker }
                }
                VStack(alignment: .leading, spacing: 10) {
                    upcomingTitle
                    if isUpcomingExpanded { horizonPicker }
                }
            }

            if !isUpcomingExpanded {
                EmptyView()
            } else if session.upcomingItems.isEmpty {
                ContentUnavailableView(
                    "当前条件下无临期订阅",
                    systemImage: "checkmark.circle",
                    description: Text("未来 \(session.dueHorizon.rawValue) 天内的项目会显示在这里。")
                )
                .frame(minHeight: 104)
            } else {
                ScrollView(.horizontal) {
                    GlassEffectContainer(spacing: 10) {
                        HStack(spacing: 10) {
                            ForEach(session.upcomingItems) { item in
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(spacing: 8) {
                                        Button {
                                            session.presentDetails(for: item.id)
                                        } label: {
                                            ServiceIconView(
                                                iconResourceName: item.iconResourceName,
                                                iconURLString: item.iconURLString,
                                                fallbackSeed: item.name,
                                                size: 24
                                            )
                                        }
                                        .buttonStyle(.plain)
                                        .help("查看订阅详情")
                                        Text(item.name).font(.headline)
                                    }
                                    Text(item.expiryDate)
                                        .foregroundStyle(.secondary)
                                    Text(item.expiryStatus)
                                        .font(.caption.weight(.medium))
                                }
                                .frame(width: 190, alignment: .leading)
                                .padding(12)
                                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 12))
                                .contentShape(.rect(cornerRadius: 12))
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
                    .padding(8)
                }
                .scrollIndicators(.hidden)
            }
        }
        .padding(16)
    }

    private var upcomingTitle: some View {
        HStack(spacing: 8) {
            Label("即将到期", systemImage: "clock.badge.exclamationmark")
                .font(.headline)
                .fixedSize()
            Button(isUpcomingExpanded ? "收起" : "展开", systemImage: isUpcomingExpanded ? "chevron.down" : "chevron.right") {
                withAnimation(.snappy) {
                    isUpcomingExpanded.toggle()
                }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
        }
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
        ToolbarItemGroup(placement: .primaryAction) {
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
                Button("CSV 导入") {}.disabled(true)
            } label: {
                Label("新建", systemImage: "plus")
            }
        }
    }

    private func shiftRange(by direction: Int) {
        centerDate = Calendar.current.date(
            byAdding: .month,
            value: session.timelineRange.rawValue * direction,
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
