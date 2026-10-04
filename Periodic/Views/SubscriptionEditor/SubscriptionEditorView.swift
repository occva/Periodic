import SwiftUI

struct SubscriptionEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(PreferenceKey.selectedCurrencies) private var selectedCurrenciesRaw = ""

    let subscription: SubscriptionDTO?
    let duplicate: SubscriptionDTO?
    let preset: SubscriptionTemplatePreset?
    private let initialNotificationSchedule: SubscriptionNotificationSchedule
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
    @State private var sharingDraft: SubscriptionSharingDraft
    @State private var amountText = ""
    @State private var currency: CurrencyCode
    @State private var hasStartDate = false
    @State private var startDate = Date()
    @State private var hasExpiryDate = false
    @State private var expiryDate = Date()
    @State private var reminderEnabled = true
    @State private var reminderTiming = SubscriptionReminderTiming.oneDayBefore
    @State private var customReminderDate = Date()
    @State private var customReminderFollowsExpiry = true
    @State private var reminderMinuteOfDay = SubscriptionNotificationSchedule.defaultMinuteOfDay
    @State private var isReminderScheduleModified = false
    @State private var automaticallyRenews = false
    @State private var note = ""
    @State private var isSaving = false
    @State private var isPresentingIconPicker = false
    @State private var isPresentingPeriodRecordChoice = false
    @State private var pendingSaveInput: SubscriptionCreateInput?
    @State private var error: PresentedError?

    init(
        subscription: SubscriptionDTO? = nil,
        duplicate: SubscriptionDTO? = nil,
        preset: SubscriptionTemplatePreset? = nil,
        onSave: @escaping @MainActor (
            SubscriptionCreateInput,
            SubscriptionUpdateHistoryPolicy
        ) async throws -> Void
    ) {
        self.subscription = subscription
        self.duplicate = duplicate
        self.preset = preset
        self.onSave = onSave
        let source = subscription ?? duplicate
        _sharingDraft = State(initialValue: SubscriptionSharingDraft(
            plan: duplicate?.sharing?.copyingMembers() ?? subscription?.sharing
        ))
        _name = State(
            initialValue: duplicate.map { $0.name + AppLocalization.string(" 副本") }
                ?? subscription?.name
                ?? preset?.name
                ?? ""
        )
        _iconResourceName = State(initialValue: source?.iconResourceName ?? preset?.iconResourceName)
        _iconURLString = State(initialValue: source?.iconURLString ?? preset?.iconURLString)
        _category = State(initialValue: source?.category ?? preset?.category ?? .other)
        _managementState = State(initialValue: source?.managementState ?? .active)
        _billingKind = State(initialValue: source?.billingKind ?? preset?.billingKind ?? .recurring)
        let cycleMonths = source?.cycleMonths ?? preset?.cycleMonths
        _billingCycle = State(initialValue: cycleMonths.flatMap(BillingCycle.init(rawValue:)) ?? .monthly)
        _amountText = State(initialValue: source?.money.inputText ?? preset?.money?.inputText ?? "")
        _currency = State(
            initialValue: source?.money.currency
                ?? preset?.money?.currency
                ?? preset?.currency
                ?? AppPreferenceValues.defaultCurrency
        )
        _hasStartDate = State(initialValue: source?.periodStart != nil)
        _startDate = State(initialValue: source?.periodStart?.date() ?? Date())
        let initialExpiryDate = source?.expiry?.date() ?? Date()
        _hasExpiryDate = State(initialValue: source?.expiry != nil)
        _expiryDate = State(initialValue: initialExpiryDate)
        _reminderEnabled = State(initialValue: source?.reminderEnabled ?? true)
        let initialAdvanceDays = source?.reminderAdvanceDays
            ?? SubscriptionNotificationSchedule.defaultAdvanceDays
        let initialMinuteOfDay = source?.reminderMinuteOfDay
            ?? SubscriptionNotificationSchedule.defaultMinuteOfDay
        let initialSchedule = SubscriptionNotificationSchedule(
            advanceDays: initialAdvanceDays,
            minuteOfDay: initialMinuteOfDay
        )
        initialNotificationSchedule = initialSchedule
        _reminderTiming = State(
            initialValue: SubscriptionReminderTiming(
                advanceDays: initialAdvanceDays,
                minuteOfDay: initialMinuteOfDay
            )
        )
        _customReminderDate = State(
            initialValue: initialSchedule.reminderDate(relativeTo: initialExpiryDate)
        )
        _customReminderFollowsExpiry = State(initialValue: true)
        _reminderMinuteOfDay = State(initialValue: initialMinuteOfDay)
        _automaticallyRenews = State(initialValue: source?.automaticallyRenews ?? false)
        _note = State(initialValue: source?.note ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(editorTitle)
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

                    Toggle("多人拼车", isOn: $sharingDraft.isEnabled)
                        .accessibilityIdentifier("subscription-sharing-enabled")

                    if !sharingDraft.isEnabled {
                        LabeledContent(AppLocalization.string(billingKind == .recurring ? "周期价格" : "一次性价格")) {
                            HStack(spacing: 8) {
                                TextField("金额", text: $amountText, prompt: Text("0.00"))
                                    .labelsHidden()
                                    .multilineTextAlignment(.trailing)
                                    .monospacedDigit()
                                    .frame(width: 150)
                                    .accessibilityIdentifier("subscription-amount")
                                Picker("币种", selection: $currency) {
                                    ForEach(CurrencyPreferences.availableCurrencies(
                                        from: selectedCurrenciesRaw,
                                        including: currency
                                    )) { currency in
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
                }

                if sharingDraft.isEnabled {
                    SubscriptionSharingEditorSection(
                        draft: $sharingDraft,
                        myAmountText: $amountText,
                        currency: $currency,
                        availableCurrencies: CurrencyPreferences.availableCurrencies(
                            from: selectedCurrenciesRaw,
                            including: currency
                        )
                    )
                }

                Section("有效期") {
                    Toggle("设置开始日期", isOn: $hasStartDate)
                    if hasStartDate {
                        DatePicker("开始日期", selection: $startDate, displayedComponents: .date)
                    }

                    if billingKind == .recurring {
                        Toggle("设置到期日期", isOn: $hasExpiryDate)
                            .accessibilityIdentifier("subscription-expiry-enabled")
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
                        Toggle(AppLocalization.string(sharingDraft.isEnabled ? "拼车续期确认" : "服务商自动续费"), isOn: $automaticallyRenews)
                            .disabled(managementState != .active)
                            .accessibilityHint("到期日提醒确认，Periodic 不会自动扣款或延长周期")

                        if reminderEnabled && !automaticallyRenews {
                            Picker("提醒时间", selection: reminderTimingBinding) {
                                ForEach(SubscriptionReminderTiming.allCases) { timing in
                                    Text(timing.title).tag(timing)
                                }
                            }
                            .pickerStyle(.menu)
                            .accessibilityIdentifier("subscription-reminder-timing")

                            if reminderTiming == .custom {
                                DatePicker(
                                    "自定义提醒时间",
                                    selection: customReminderDateBinding,
                                    in: ...customReminderLatestDate,
                                    displayedComponents: [.date, .hourAndMinute]
                                )
                                .disabled(!hasExpiryDate)

                                if !hasExpiryDate {
                                    Text("请先设置到期日期，再选择自定义提醒时间。")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }

                        if automaticallyRenews {
                            DatePicker(
                                "提醒时间",
                                selection: reminderTimeBinding,
                                displayedComponents: .hourAndMinute
                            )
                        }

                        Text(reminderExplanation)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    TextField("备注", text: $note, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .onChange(of: expiryDate) { previousExpiryDate, expiryDate in
                customReminderDate = SubscriptionNotificationSchedule
                    .adjustedCustomReminderDate(
                        current: customReminderDate,
                        previousExpiryDate: previousExpiryDate,
                        expiryDate: expiryDate,
                        followsExpiry: customReminderFollowsExpiry
                    )
            }

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
                automaticallyRenews = false
            } else {
                reminderEnabled = true
            }
        }
        .onChange(of: automaticallyRenews) { _, isEnabled in
            if isEnabled {
                hasExpiryDate = true
            }
        }
        .onChange(of: managementState) { _, state in
            if state != .active {
                automaticallyRenews = false
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

    private var editorTitle: String {
        if subscription != nil { return AppLocalization.string("编辑订阅") }
        if duplicate != nil { return AppLocalization.string("复制订阅") }
        return AppLocalization.string("新建订阅")
    }

    private var reminderExplanation: String {
        if automaticallyRenews {
            return AppLocalization.string(sharingDraft.isEnabled
                ? "拼车续期只在到期日提醒确认，不会自动支付或延长周期。"
                : "服务商自动续费只在到期日提醒一次，避免与普通到期提醒重复。"
            )
        }
        return AppLocalization.string(
            "预设提醒会在本地时间 09:00 发送；自定义可选择具体日期和时间。"
        )
    }

    private var reminderTimeBinding: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(
                    byAdding: .minute,
                    value: reminderMinuteOfDay,
                    to: Calendar.current.startOfDay(for: Date())
                ) ?? Date()
            },
            set: { date in
                let components = Calendar.current.dateComponents([.hour, .minute], from: date)
                let minuteOfDay = (components.hour ?? 9) * 60 + (components.minute ?? 0)
                guard reminderMinuteOfDay != minuteOfDay else { return }
                reminderMinuteOfDay = minuteOfDay
                isReminderScheduleModified = true
            }
        )
    }

    private var reminderTimingBinding: Binding<SubscriptionReminderTiming> {
        Binding(
            get: { reminderTiming },
            set: { timing in
                guard reminderTiming != timing else { return }
                reminderTiming = timing
                isReminderScheduleModified = true
            }
        )
    }

    private var customReminderDateBinding: Binding<Date> {
        Binding(
            get: { customReminderDate },
            set: { date in
                guard customReminderDate != date else { return }
                customReminderDate = date
                customReminderFollowsExpiry = false
                isReminderScheduleModified = true
            }
        )
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
        let notificationSchedule = billingKind == .recurring
            ? try notificationSchedule(expiry: expiry)
            : .default

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
            sharing: try sharingDraft.plan(myMoney: money),
            note: note,
            reminderEnabled: billingKind == .recurring && reminderEnabled,
            reminderAdvanceDays: notificationSchedule.advanceDays,
            reminderMinuteOfDay: notificationSchedule.minuteOfDay,
            automaticallyRenews: billingKind == .recurring
                && managementState == .active
                && hasExpiryDate
                && automaticallyRenews
        )
    }

    private var customReminderLatestDate: Date {
        Calendar.current.date(
            bySettingHour: 23,
            minute: 59,
            second: 59,
            of: expiryDate
        ) ?? expiryDate
    }

    private func notificationSchedule(
        expiry: LocalDate?
    ) throws -> SubscriptionNotificationSchedule {
        if automaticallyRenews {
            return SubscriptionNotificationSchedule(
                advanceDays: [0],
                minuteOfDay: reminderMinuteOfDay
            )
        }
        guard reminderEnabled, isReminderScheduleModified else {
            return initialNotificationSchedule
        }
        let editedSchedule: SubscriptionNotificationSchedule
        if let advanceDays = reminderTiming.advanceDays {
            editedSchedule = SubscriptionNotificationSchedule(
                advanceDays: [advanceDays],
                minuteOfDay: SubscriptionNotificationSchedule.defaultMinuteOfDay
            )
        } else {
            guard let expiry else {
                throw EditorValidationError.customReminderRequiresExpiry
            }
            guard let schedule = SubscriptionNotificationSchedule(
                reminderDate: customReminderDate,
                expiry: expiry
            ) else {
                throw EditorValidationError.customReminderAfterExpiry
            }
            editedSchedule = schedule
        }
        return SubscriptionNotificationSchedule.resolvingEditorSchedule(
            initial: initialNotificationSchedule,
            edited: editedSchedule,
            isModified: isReminderScheduleModified
        )
    }
}

private enum EditorValidationError: LocalizedError {
    case emptyName
    case invalidDateRange
    case customReminderRequiresExpiry
    case customReminderAfterExpiry

    var errorDescription: String? {
        switch self {
        case .emptyName: "请输入订阅名称。"
        case .invalidDateRange: "到期日期不能早于开始日期。"
        case .customReminderRequiresExpiry: "请先设置到期日期，再选择自定义提醒时间。"
        case .customReminderAfterExpiry: "自定义提醒时间不能晚于到期日期。"
        }
    }
}

private enum SubscriptionReminderTiming: String, CaseIterable, Identifiable {
    case oneDayBefore
    case threeDaysBefore
    case sevenDaysBefore
    case custom

    var id: Self { self }

    init(advanceDays: [Int], minuteOfDay: Int) {
        guard advanceDays.count == 1,
              minuteOfDay == SubscriptionNotificationSchedule.defaultMinuteOfDay else {
            self = .custom
            return
        }
        self = switch advanceDays[0] {
        case 1: .oneDayBefore
        case 3: .threeDaysBefore
        case 7: .sevenDaysBefore
        default: .custom
        }
    }

    var advanceDays: Int? {
        switch self {
        case .oneDayBefore: 1
        case .threeDaysBefore: 3
        case .sevenDaysBefore: 7
        case .custom: nil
        }
    }

    var title: String {
        switch self {
        case .oneDayBefore: AppLocalization.string("提前 1 天")
        case .threeDaysBefore: AppLocalization.string("提前 3 天")
        case .sevenDaysBefore: AppLocalization.string("提前 7 天")
        case .custom: AppLocalization.string("自定义时间")
        }
    }
}

#Preview {
    SubscriptionEditorView { _, _ in }
}
