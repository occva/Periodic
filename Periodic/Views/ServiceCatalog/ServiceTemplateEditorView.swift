import SwiftUI

struct ServiceTemplateEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let template: ServiceTemplateDTO?
    let customCategories: [TemplateCategoryDTO]
    let onSave: @MainActor (ServiceTemplateInput) async throws -> Void

    @State private var name: String
    @State private var aliasesText: String
    @State private var categoryChoice: TemplateCategoryChoice
    @State private var iconResourceName: String?
    @State private var iconURLString: String?
    @State private var billingKind: BillingKind
    @State private var billingCycle: BillingCycle
    @State private var amountText: String
    @State private var currency: CurrencyCode
    @State private var isSaving = false
    @State private var isPresentingIconPicker = false
    @State private var error: PresentedError?

    init(
        template: ServiceTemplateDTO? = nil,
        customCategories: [TemplateCategoryDTO] = [],
        onSave: @escaping @MainActor (ServiceTemplateInput) async throws -> Void
    ) {
        self.template = template
        self.customCategories = customCategories
        self.onSave = onSave
        _name = State(initialValue: template?.name ?? "")
        _aliasesText = State(initialValue: template?.aliases.joined(separator: "，") ?? "")
        if let customCategoryID = template?.customCategoryID {
            _categoryChoice = State(initialValue: .custom(customCategoryID))
        } else {
            _categoryChoice = State(initialValue: .builtin(template?.category ?? .other))
        }
        _iconResourceName = State(initialValue: template?.iconResourceName)
        _iconURLString = State(initialValue: template?.iconURLString)
        _billingKind = State(initialValue: template?.suggestedBillingKind ?? .recurring)
        _billingCycle = State(initialValue: template?.suggestedCycleMonths.flatMap(BillingCycle.init(rawValue:)) ?? .monthly)
        _amountText = State(initialValue: template?.suggestedMoney?.inputText ?? "")
        _currency = State(initialValue: template?.currency ?? AppPreferenceValues.defaultCurrency)
    }

    var body: some View {
        Form {
            Section("模板资料") {
                TextField("名称", text: $name)
                TextField("别名", text: $aliasesText, prompt: Text("多个别名用逗号分隔"))
                Picker("模板分类", selection: $categoryChoice) {
                    Section("内置分类") {
                        ForEach(ServiceCategory.allCases) { value in
                            Text(value.title).tag(TemplateCategoryChoice.builtin(value))
                        }
                    }
                    if !customCategories.isEmpty {
                        Section("我的分类") {
                            ForEach(customCategories) { category in
                                Text(category.name).tag(TemplateCategoryChoice.custom(category.id))
                            }
                        }
                    }
                }
            }

            Section("品牌图标") {
                HStack(spacing: 12) {
                    ServiceIconView(
                        iconResourceName: iconResourceName,
                        iconURLString: iconURLString,
                        fallbackSeed: name,
                        size: 52
                    )
                    Spacer()
                    if iconResourceName != nil || iconURLString != nil {
                        Button("移除") {
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

            Section("建议计费") {
                Picker("计费类型", selection: $billingKind) {
                    ForEach(BillingKind.allCases) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                .pickerStyle(.segmented)

                if billingKind == .recurring {
                    Picker("建议周期", selection: $billingCycle) {
                        ForEach(BillingCycle.allCases) { cycle in
                            Text(cycle.title).tag(cycle)
                        }
                    }
                }

                LabeledContent("建议金额（可留空）") {
                    HStack(spacing: 8) {
                        TextField("金额", text: $amountText)
                            .labelsHidden()
                            .multilineTextAlignment(.trailing)
                            .frame(width: 150)
                        Picker("币种", selection: $currency) {
                            ForEach(CurrencyCode.allCases) { value in
                                Text(value.rawValue).tag(value)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 92)
                    }
                }
            }

            Section {
                HStack {
                    Spacer()
                    Button("取消") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                        .disabled(isSaving)
                        .buttonStyle(.glass)
                    Button("保存模板", action: save)
                        .keyboardShortcut(.defaultAction)
                        .disabled(isSaving)
                        .buttonStyle(.glassProminent)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(navigationTitle)
        .frame(minWidth: 620, maxWidth: 720, minHeight: 600, maxHeight: 700)
        .sheet(isPresented: $isPresentingIconPicker) {
            AppleIconPickerView(initialQuery: name) { reference in
                iconResourceName = nil
                iconURLString = reference
            }
        }
        .errorAlert($error)
    }

    private var navigationTitle: String {
        guard let template else { return "新建我的模板" }
        return template.source == .builtin ? "复制为我的模板" : "编辑我的模板"
    }

    private func save() {
        do {
            let input = try validatedInput()
            isSaving = true
            Task { @MainActor in
                do {
                    try await onSave(input)
                    dismiss()
                } catch {
                    self.error = PresentedError(error, title: "无法保存模板")
                    isSaving = false
                }
            }
        } catch {
            self.error = PresentedError(error, title: "请检查模板")
        }
    }

    private func validatedInput() throws -> ServiceTemplateInput {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { throw TemplateValidationError.emptyName }
        let aliases = aliasesText
            .components(separatedBy: CharacterSet(charactersIn: ",，"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let money = amountText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? nil
            : try Money.parse(amountText, currency: currency)
        let userID: UUID
        if case .user(let id) = template?.key {
            userID = id
        } else {
            userID = UUID()
        }
        let category: ServiceCategory
        let customCategoryID: UUID?
        switch categoryChoice {
        case .builtin(let value):
            category = value
            customCategoryID = nil
        case .custom(let id):
            category = .other
            customCategoryID = id
        }

        return ServiceTemplateInput(
            id: userID,
            expectedRevision: template?.revision,
            name: trimmedName,
            aliases: aliases,
            category: category,
            customCategoryID: customCategoryID,
            symbolName: PlaceholderSymbolResolver.symbol(for: trimmedName),
            iconResourceName: iconResourceName,
            iconURLString: iconURLString,
            suggestedBillingKind: billingKind,
            suggestedCycleMonths: billingKind == .recurring ? billingCycle.rawValue : nil,
            suggestedMoney: money,
            currency: currency
        )
    }
}

private enum TemplateCategoryChoice: Hashable {
    case builtin(ServiceCategory)
    case custom(UUID)
}

private enum TemplateValidationError: LocalizedError {
    case emptyName

    var errorDescription: String? { "请输入模板名称。" }
}
