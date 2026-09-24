import SwiftUI

struct SubscriptionReminderCenterView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.currencyDisplayStyle) private var currencyDisplayStyle

    let reminderItems: [SubscriptionListItem]
    let referenceDate: LocalDate
    let previewRenewal: (UUID) -> SubscriptionRenewalPreview?
    let confirmRenewal: @MainActor (SubscriptionRenewalRequest) async throws -> Void
    let markNotRenewed: @MainActor (SubscriptionNonRenewalRequest) async throws -> Void
    let onDetails: (UUID) -> Void

    @State private var scope: SubscriptionReminderScope
    @State private var renewalActionPreview: SubscriptionRenewalPreview?
    @State private var renewalEditorPreview: SubscriptionRenewalPreview?
    @State private var nonRenewalPreview: SubscriptionRenewalPreview?
    @State private var confirmingSubscriptionID: UUID?
    @State private var error: PresentedError?

    init(
        initialScope: SubscriptionReminderScope,
        reminderItems: [SubscriptionListItem],
        referenceDate: LocalDate,
        previewRenewal: @escaping (UUID) -> SubscriptionRenewalPreview?,
        confirmRenewal: @escaping @MainActor (SubscriptionRenewalRequest) async throws -> Void,
        markNotRenewed: @escaping @MainActor (SubscriptionNonRenewalRequest) async throws -> Void,
        onDetails: @escaping (UUID) -> Void
    ) {
        self.reminderItems = reminderItems
        self.referenceDate = referenceDate
        self.previewRenewal = previewRenewal
        self.confirmRenewal = confirmRenewal
        self.markNotRenewed = markNotRenewed
        self.onDetails = onDetails
        _scope = State(initialValue: initialScope)
    }

    var body: some View {
        VStack(spacing: 0) {
            scopePicker
                .padding(12)

            Divider()

            Group {
                if displayedItems.isEmpty {
                    ContentUnavailableView(
                        emptyTitle,
                        systemImage: "bell.slash",
                        description: Text(emptyDescription)
                    )
                } else {
                    reminderList
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            HStack {
                Spacer()
                Button("关闭", systemImage: "xmark") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.glass)
            }
            .padding(16)
        }
        .frame(width: 740, height: 620)
        .presentationSizing(.fitted)
        .confirmationDialog(
            "选择续费方式",
            isPresented: Binding(
                get: { renewalActionPreview != nil },
                set: { if !$0 { renewalActionPreview = nil } }
            ),
            titleVisibility: .visible,
            presenting: renewalActionPreview
        ) { preview in
            Button("按当前周期续费") { confirmCurrentTerms(preview) }
            Button("自定义续费…") { renewalEditorPreview = preview }
            Button("取消", role: .cancel) {}
        } message: { preview in
            Text(currentTermsDescription(preview))
        }
        .confirmationDialog(
            "确认本期未续费？",
            isPresented: Binding(
                get: { nonRenewalPreview != nil },
                set: { if !$0 { nonRenewalPreview = nil } }
            ),
            titleVisibility: .visible,
            presenting: nonRenewalPreview
        ) { preview in
            Button("标记未续费", role: .destructive) { markAsNotRenewed(preview) }
            Button("取消", role: .cancel) {}
        } message: { _ in
            Text("将关闭服务商自动续费并保留当前到期状态，不会新增周期记录。")
        }
        .sheet(item: $renewalEditorPreview) { preview in
            SubscriptionRenewalEditorView(
                preview: preview,
                confirmRenewal: confirmRenewal
            )
        }
        .errorAlert($error)
    }

    private var scopePicker: some View {
        Picker("提醒范围", selection: $scope) {
            ForEach(SubscriptionReminderScope.allCases) { option in
                Text("\(option.title)  \(itemCount(for: option))")
                    .tag(option)
            }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .frame(width: 500)
    }

    private var reminderList: some View {
        List(displayedItems) { item in
            reminderRow(
                item,
                allowsConfirmation: pendingRenewalIDs.contains(item.id)
            )
        }
        .listStyle(.inset)
    }

    private var displayedItems: [SubscriptionListItem] {
        switch scope {
        case .all: reminderItems
        case .today: reminderItems.filter(isDueToday)
        case .pendingRenewal: reminderItems.filter(isPendingRenewal)
        }
    }

    private var pendingRenewalIDs: Set<UUID> {
        Set(reminderItems.filter(isPendingRenewal).map(\.id))
    }

    private func itemCount(for option: SubscriptionReminderScope) -> Int {
        switch option {
        case .all: reminderItems.count
        case .today: reminderItems.count(where: isDueToday)
        case .pendingRenewal: pendingRenewalIDs.count
        }
    }

    private func isDueToday(_ item: SubscriptionListItem) -> Bool {
        item.remainingDayCount(relativeTo: referenceDate) == 0
    }

    private func isPendingRenewal(_ item: SubscriptionListItem) -> Bool {
        item.isPendingAutomaticRenewal(relativeTo: referenceDate)
    }

    private var emptyTitle: String {
        switch scope {
        case .all: AppLocalization.string("暂无提醒")
        case .today: AppLocalization.string("今日没有到期提醒")
        case .pendingRenewal: AppLocalization.string("暂无待续费项目")
        }
    }

    private var emptyDescription: String {
        switch scope {
        case .all:
            AppLocalization.string("临近到期与待续费项目会显示在这里。")
        case .today:
            AppLocalization.string("今天到期且已启用提醒的项目会显示在这里。")
        case .pendingRenewal:
            AppLocalization.string("到期后需要处理的自动续费会显示在这里。")
        }
    }

    private func reminderRow(
        _ item: SubscriptionListItem,
        allowsConfirmation: Bool
    ) -> some View {
        HStack(spacing: 12) {
            ServiceIconView(
                iconResourceName: item.iconResourceName,
                iconURLString: item.iconURLString,
                fallbackSeed: item.name,
                size: 32
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(statusText(for: item))
                    .font(.caption)
                    .foregroundStyle(allowsConfirmation ? .orange : .secondary)
            }
            .frame(width: 230, alignment: .leading)
            .help(item.name)

            VStack(alignment: .trailing, spacing: 3) {
                Text(item.paymentSummary(style: currencyDisplayStyle))
                    .monospacedDigit()
                Text(item.expiryDate)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .frame(width: 155, alignment: .trailing)

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                if allowsConfirmation {
                    Button("未续费") {
                        nonRenewalPreview = loadPreview(for: item.id)
                    }
                    .buttonStyle(.glass)
                    .disabled(confirmingSubscriptionID != nil)

                    Button("已续费") {
                        renewalActionPreview = loadPreview(for: item.id)
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(confirmingSubscriptionID != nil)
                }

                Button("查看详情") {
                    onDetails(item.id)
                }
            }
            .fixedSize()
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
    }

    private func statusText(for item: SubscriptionListItem) -> String {
        guard let remainingDays = item.remainingDayCount(relativeTo: referenceDate) else {
            return AppLocalization.string("日期未知")
        }
        return switch remainingDays {
        case ..<0:
            String(
                format: AppLocalization.string("已逾期 %d 天"),
                abs(remainingDays)
            )
        case 0:
            AppLocalization.string("今天到期")
        default:
            String(
                format: AppLocalization.string("%d 天后到期"),
                remainingDays
            )
        }
    }

    private func loadPreview(for id: UUID) -> SubscriptionRenewalPreview? {
        guard let preview = previewRenewal(id) else {
            error = PresentedError(
                SubscriptionReminderError.previewUnavailable,
                title: "无法处理续费"
            )
            return nil
        }
        return preview
    }

    private func cycleTitle(_ months: Int) -> String {
        BillingCycle(rawValue: months)?.title ?? AppLocalization.string("自定义")
    }

    private func currentTermsDescription(_ preview: SubscriptionRenewalPreview) -> String {
        String(
            format: AppLocalization.string("当前方案为 %@，%@。"),
            cycleTitle(preview.cycleMonths),
            preview.money.displayText(style: currencyDisplayStyle)
        )
    }

    private func confirmCurrentTerms(_ preview: SubscriptionRenewalPreview) {
        confirmingSubscriptionID = preview.subscriptionID
        renewalActionPreview = nil
        let request = SubscriptionRenewalRequest(
            subscriptionID: preview.subscriptionID,
            expectedRevision: preview.expectedRevision,
            expectedExpiry: preview.previousExpiry,
            cycleMonths: preview.cycleMonths,
            money: preview.money
        )
        Task { @MainActor in
            do {
                try await confirmRenewal(request)
                confirmingSubscriptionID = nil
            } catch {
                self.error = PresentedError(error, title: "无法确认续费")
                confirmingSubscriptionID = nil
            }
        }
    }

    private func markAsNotRenewed(_ preview: SubscriptionRenewalPreview) {
        confirmingSubscriptionID = preview.subscriptionID
        nonRenewalPreview = nil
        let request = SubscriptionNonRenewalRequest(
            subscriptionID: preview.subscriptionID,
            expectedRevision: preview.expectedRevision,
            expectedExpiry: preview.previousExpiry
        )
        Task { @MainActor in
            do {
                try await markNotRenewed(request)
                confirmingSubscriptionID = nil
            } catch {
                self.error = PresentedError(error, title: "无法标记未续费")
                confirmingSubscriptionID = nil
            }
        }
    }
}

private enum SubscriptionReminderError: LocalizedError {
    case previewUnavailable

    var errorDescription: String? {
        "订阅状态已变化，请关闭列表后重试。"
    }
}
