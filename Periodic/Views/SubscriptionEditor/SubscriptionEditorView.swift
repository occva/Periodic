import SwiftUI

struct SubscriptionEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let subscription: SubscriptionDTO?
    let preset: SubscriptionTemplatePreset?
    let onSave: @MainActor (
        SubscriptionCreateInput,
        SubscriptionUpdateHistoryPolicy
    ) async throws -> Void

    @State private var name = ""
    @State private var iconResourceName: String?
    @State private var iconURLString: String?
    @State private var category = ServiceCategory.other
    @State private var managementState = ManagementState.active
    @State private var billingKind = BillingKind.recurring
    @State private var billingCycle = BillingCycle.monthly
    @State private var amountText = ""
    @State private var currency: CurrencyCode
    @State private var hasStartDate = false
    @State private var startDate = Date()
    @State private var hasExpiryDate = false
    @State private var expiryDate = Date()
    @State private var reminderEnabled = true
    @State private var note = ""
    @State private var isSaving = false
    @State private var isPresentingIconPicker = false
    @State private var isPresentingPeriodRecordChoice = false
    @State private var pendingSaveInput: SubscriptionCreateInput?
    @State private var error: PresentedError?

    init(
        subscription: SubscriptionDTO? = nil,
        preset: SubscriptionTemplatePreset? = nil,
        onSave: @escaping @MainActor (
            SubscriptionCreateInput,
            SubscriptionUpdateHistoryPolicy
        ) async throws -> Void
    ) {
        self.subscription = subscription
        self.preset = preset
        self.onSave = onSave
        _name = State(initialValue: subscription?.name ?? preset?.name ?? "")
        _iconResourceName = State(initialValue: subscription?.iconResourceName ?? preset?.iconResourceName)
        _iconURLString = State(initialValue: subscription?.iconURLString ?? preset?.iconURLString)
        _category = State(initialValue: subscription?.category ?? preset?.category ?? .other)
        _managementState = State(initialValue: subscription?.managementState ?? .active)
        _billingKind = State(initialValue: subscription?.billingKind ?? preset?.billingKind ?? .recurring)
        let cycleMonths = subscription?.cycleMonths ?? preset?.cycleMonths
        _billingCycle = State(initialValue: cycleMonths.flatMap(BillingCycle.init(rawValue:)) ?? .monthly)
        _amountText = State(initialValue: subscription?.money.inputText ?? preset?.money?.inputText ?? "")
        _currency = State(
            initialValue: subscription?.money.currency
                ?? preset?.money?.currency
                ?? preset?.currency
                ?? AppPreferenceValues.defaultCurrency
        )
        _hasStartDate = State(initialValue: subscription?.periodStart != nil)
        _startDate = State(initialValue: subscription?.periodStart?.date() ?? Date())
        _hasExpiryDate = State(initialValue: subscription?.expiry != nil)
        _expiryDate = State(initialValue: subscription?.expiry?.date() ?? Date())
        _reminderEnabled = State(initialValue: subscription?.reminderEnabled ?? true)
        _note = State(initialValue: subscription?.note ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(subscription == nil ? "新建订阅" : "编辑订阅")
                    .font(.title2.weight(.semibold))
                Spacer()
            }
            .padding(20)

            Divider()

            Form {
                Section("基本信息") {
                    TextField("名称", text: $name, prompt: Text("例如：哔哩哔哩大会员"))
                        .accessibilityIdentifier("subscription-name")

                    Picker("服务类型", selection: $category) {
                        ForEach(ServiceCategory.allCases) { category in
                            Text(category.title).tag(category)
                        }
                    }

                    Picker("管理状态", selection: $managementState) {
                        ForEach(ManagementState.allCases) { state in
                            Text(state.title).tag(state)
                        }
                    }
                }

                Section("图标") {
                    HStack(spacing: 12) {
                        ServiceIconView(
                            iconResourceName: iconResourceName,
                            iconURLString: iconURLString,
                            fallbackSeed: name,
                            size: 44
                        )
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(iconDescription)
                        Spacer()
                        if iconResourceName != nil || iconURLString != nil {
                            Button("移除图片") {
                                iconResourceName = nil
                                iconURLString = nil
                            }
                        }
                        LocalIconPickerButton { reference in
                            iconResourceName = nil
                            iconURLString = reference
                        }
                        Button("Apple 搜索…") { isPresentingIconPicker = true }
                            .accessibilityIdentifier("search-apple-icon")
                    }
                }

                Section("计费与价格") {
                    Picker("计费类型", selection: $billingKind) {
                        ForEach(BillingKind.allCases) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)

                    if billingKind == .recurring {
                        Picker("周期", selection: $billingCycle) {
                            ForEach(BillingCycle.allCases) { cycle in
                                Text(cycle.title).tag(cycle)
                            }
                        }
                    }

                    LabeledContent(billingKind == .recurring ? "周期价格" : "一次性价格") {
                        HStack(spacing: 8) {
                            TextField("金额", text: $amountText, prompt: Text("0.00"))
                                .labelsHidden()
                                .multilineTextAlignment(.trailing)
                                .frame(width: 150)
                                .accessibilityIdentifier("subscription-amount")

                            Picker("币种", selection: $currency) {
                                ForEach(CurrencyCode.allCases) { currency in
                                    Text(currency.rawValue).tag(currency)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(width: 92)
                            .accessibilityIdentifier("subscription-currency")
                        }
                    }
                }

                Section("有效期") {
                    Toggle("设置开始日期", isOn: $hasStartDate)
                    if hasStartDate {
                        DatePicker("开始日期", selection: $startDate, displayedComponents: .date)
                    }

                    if billingKind == .recurring {
                        Toggle("设置到期日期", isOn: $hasExpiryDate)
                        if hasExpiryDate {
                            DatePicker("到期日期", selection: $expiryDate, displayedComponents: .date)
                                .accessibilityIdentifier("subscription-expiry")
                        }
                    } else {
                        LabeledContent("有效期", value: "永久有效")
                    }
                }

                Section("提醒与备注") {
                    if billingKind == .recurring {
                        Toggle("到期提醒", isOn: $reminderEnabled)
                    }

                    TextField("备注", text: $note, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            Divider()

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(isSaving)
                    .buttonStyle(.glass)
                Button {
                    save()
                } label: {
                    if isSaving {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("保存")
                    }
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(isSaving)
                .accessibilityIdentifier("save-subscription")
                .buttonStyle(.glassProminent)
            }
            .padding(16)
        }
        .frame(minWidth: 620, maxWidth: 720, minHeight: 660, maxHeight: 740)
        .onChange(of: billingKind) { _, kind in
            if kind == .lifetime {
                hasExpiryDate = false
                reminderEnabled = false
            } else {
                reminderEnabled = true
            }
        }
        .errorAlert($error)
        .sheet(isPresented: $isPresentingIconPicker) {
            AppleIconPickerView(initialQuery: name) { reference in
                iconResourceName = nil
                iconURLString = reference
            }
        }
        .confirmationDialog(
            canAddPendingPeriodRecord ? "是否添加周期记录？" : "日期不完整",
            isPresented: $isPresentingPeriodRecordChoice,
            titleVisibility: .visible
        ) {
            if canAddPendingPeriodRecord {
                Button("更新并添加周期记录") {
                    savePendingInput(historyPolicy: .appendPeriodRecord)
                }
                .accessibilityIdentifier("save-and-add-period")
            }
            Button("仅更新当前设置") {
                savePendingInput(historyPolicy: .currentOnly)
            }
            .accessibilityIdentifier("save-current-only")
            Button("返回编辑", role: .cancel) {
                pendingSaveInput = nil
            }
        } message: {
            Text(periodRecordChoiceMessage)
        }
    }

    private var iconDescription: String {
        if iconResourceName != nil { return "使用内置品牌图标" }
        if iconURLString != nil { return "已设置自定义品牌图标" }
        return "未设置品牌图标，当前使用占位图标"
    }

    private func save() {
        do {
            let input = try validatedInput()
            if shouldAskForPeriodRecord(for: input) {
                pendingSaveInput = input
                isPresentingPeriodRecordChoice = true
            } else {
                persist(input, historyPolicy: .currentOnly)
            }
        } catch {
            self.error = PresentedError(error, title: "请检查表单")
        }
    }

    private var canAddPendingPeriodRecord: Bool {
        guard let input = pendingSaveInput else { return false }
        return input.periodStart != nil && input.expiry != nil
    }

    private var periodRecordChoiceMessage: String {
        if canAddPendingPeriodRecord {
            return "当前周期时间已经改变。是否将修改后的周期和当前价格同时保存为一条周期记录？"
        }
        return "当前周期缺少开始日期或到期日期，无法形成完整记录。本次可以仅更新当前设置，或返回补充日期。"
    }

    private func shouldAskForPeriodRecord(for input: SubscriptionCreateInput) -> Bool {
        guard let subscription,
              input.billingKind == .recurring else {
            return false
        }
        return subscription.billingKind != input.billingKind
            || subscription.periodStart != input.periodStart
            || subscription.expiry != input.expiry
            || subscription.cycleMonths != input.cycleMonths
    }

    private func savePendingInput(historyPolicy: SubscriptionUpdateHistoryPolicy) {
        guard let input = pendingSaveInput else { return }
        pendingSaveInput = nil
        persist(input, historyPolicy: historyPolicy)
    }

    private func persist(
        _ input: SubscriptionCreateInput,
        historyPolicy: SubscriptionUpdateHistoryPolicy
    ) {
        isSaving = true
        Task { @MainActor in
            do {
                try await onSave(input, historyPolicy)
                dismiss()
            } catch {
                self.error = PresentedError(error, title: "无法保存订阅")
                isSaving = false
            }
        }
    }

    private func validatedInput() throws -> SubscriptionCreateInput {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { throw EditorValidationError.emptyName }
        let money = try Money.parse(amountText, currency: currency)
        let start = hasStartDate ? LocalDate(startDate) : nil
        let expiry = billingKind == .recurring && hasExpiryDate ? LocalDate(expiryDate) : nil
        if let start, let expiry, start > expiry {
            throw EditorValidationError.invalidDateRange
        }

        return SubscriptionCreateInput(
            id: subscription?.id ?? UUID(),
            name: trimmedName,
            symbolName: PlaceholderSymbolResolver.symbol(for: trimmedName),
            iconResourceName: iconResourceName,
            iconURLString: iconURLString,
            category: category,
            managementState: managementState,
            billingKind: billingKind,
            periodStart: start,
            expiry: expiry,
            cycleMonths: billingKind == .recurring ? billingCycle.rawValue : nil,
            money: money,
            note: note,
            reminderEnabled: billingKind == .recurring && reminderEnabled
        )
    }
}

private enum EditorValidationError: LocalizedError {
    case emptyName
    case invalidDateRange

    var errorDescription: String? {
        switch self {
        case .emptyName: "请输入订阅名称。"
        case .invalidDateRange: "到期日期不能早于开始日期。"
        }
    }
}

#Preview {
    SubscriptionEditorView { _, _ in }
}
