import SwiftUI

enum TemplateLibraryPresentation {
    case sheet
    case embedded
}

struct TemplateLibraryView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss

    let presentation: TemplateLibraryPresentation
    let onSelectPreset: (@MainActor (SubscriptionTemplatePreset) -> Void)?
    let onCreateSubscription: @MainActor (SubscriptionCreateInput) async throws -> Void

    @State private var userTemplates: [ServiceTemplateDTO] = []
    @State private var customCategories: [TemplateCategoryDTO] = []
    @State private var builtinCategoryAssignments: [String: TemplateCategoryAssignment] = [:]
    @State private var searchText = ""
    @State private var selection = TemplateLibrarySelection.all
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @State private var groupByCategory = false
    @State private var selectedPreset: SubscriptionTemplatePreset?
    @State private var templateEditorRoute: TemplateEditorRoute?
    @State private var categoryEditorRoute: TemplateCategoryEditorRoute?
    @State private var pendingTemplateDeletion: ServiceTemplateDTO?
    @State private var pendingCategoryDeletion: TemplateCategoryDTO?
    @State private var error: PresentedError?

    private let columns = [GridItem(.adaptive(minimum: 190, maximum: 280), spacing: 12)]
    private let contentPadding: CGFloat = 16

    init(
        presentation: TemplateLibraryPresentation,
        onSelectPreset: (@MainActor (SubscriptionTemplatePreset) -> Void)? = nil,
        onCreateSubscription: @escaping @MainActor (SubscriptionCreateInput) async throws -> Void
    ) {
        self.presentation = presentation
        self.onSelectPreset = onSelectPreset
        self.onCreateSubscription = onCreateSubscription
    }

    var body: some View {
        libraryLayout
        .searchable(
            text: $searchText,
            placement: .toolbar,
            prompt: "搜索模板名称或别名"
        )
        .onAppear { columnVisibility = .all }
        .frame(
            minWidth: presentation == .sheet ? 900 : 0,
            idealWidth: presentation == .sheet ? 1100 : nil,
            minHeight: presentation == .sheet ? 620 : 0,
            idealHeight: presentation == .sheet ? 720 : nil
        )
        .task(id: services.templateDataVersion) { await reloadLibrary() }
        .sheet(item: $categoryEditorRoute) { route in
            TemplateCategoryEditorView(category: route.category) { input in
                guard let store = services.templateCategoryStore else {
                    throw TemplateLibraryError.categoryStoreUnavailable
                }
                try await store.save(input)
                services.notifyTemplateDataChanged()
                await reloadLibrary()
            }
        }
        .confirmationDialog(
            "删除“\(pendingTemplateDeletion?.name ?? "")”？",
            isPresented: Binding(
                get: { pendingTemplateDeletion != nil },
                set: { if !$0 { pendingTemplateDeletion = nil } }
            )
        ) {
            Button("删除模板", role: .destructive) {
                guard let template = pendingTemplateDeletion else { return }
                pendingTemplateDeletion = nil
                delete(template)
            }
            Button("取消", role: .cancel) { pendingTemplateDeletion = nil }
        } message: {
            Text("只删除模板，不会改动已经创建的订阅。")
        }
        .confirmationDialog(
            "删除分类“\(pendingCategoryDeletion?.name ?? "")”？",
            isPresented: Binding(
                get: { pendingCategoryDeletion != nil },
                set: { if !$0 { pendingCategoryDeletion = nil } }
            )
        ) {
            Button("删除分类", role: .destructive) {
                guard let category = pendingCategoryDeletion else { return }
                pendingCategoryDeletion = nil
                delete(category)
            }
            Button("取消", role: .cancel) { pendingCategoryDeletion = nil }
        } message: {
            Text("分类中的模板会保留，并移动到“其他”。")
        }
        .errorAlert($error)
    }

    @ViewBuilder
    private var libraryLayout: some View {
        switch presentation {
        case .sheet:
            NavigationSplitView(columnVisibility: $columnVisibility) {
                sidebar
                    .navigationSplitViewColumnWidth(min: 210, ideal: 240, max: 280)
            } detail: {
                libraryDetail
            }
        case .embedded:
            NavigationStack {
                HStack(spacing: 0) {
                    sidebar
                        .frame(width: 240)
                    Divider()
                    libraryDetail
                }
            }
        }
    }

    private var libraryDetail: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .navigationTitle(selectionTitle)
        .toolbar { toolbarContent }
        .accessibilityIdentifier("template-library-content")
        .navigationDestination(item: $selectedPreset) { preset in
            SubscriptionEditorView(preset: preset) { input, _ in
                try await onCreateSubscription(input)
                if presentation == .sheet {
                    dismiss()
                } else {
                    selectedPreset = nil
                }
            }
        }
        .navigationDestination(item: $templateEditorRoute) { route in
            ServiceTemplateEditorView(
                template: route.template,
                customCategories: customCategories
            ) { input in
                guard let store = services.templateStore else {
                    throw TemplateLibraryError.storeUnavailable
                }
                try await store.save(input)
                services.notifyTemplateDataChanged()
                await reloadUserTemplates()
            }
        }
    }

    private var sidebar: some View {
        TemplateLibrarySidebar(
            selection: $selection,
            allTemplates: allTemplates,
            builtinTemplates: builtinTemplates,
            userTemplates: userTemplates,
            customCategories: customCategories,
            onEditCategory: { category in
                categoryEditorRoute = TemplateCategoryEditorRoute(category: category)
            },
            onDeleteCategory: { category in
                pendingCategoryDeletion = category
            },
            onMoveTemplate: { templateID, target in
                moveTemplate(id: templateID, to: target)
            }
        )
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if presentation == .sheet {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        } else {
            ToolbarItem(placement: .primaryAction) {
                Toggle(isOn: $groupByCategory) {
                    Label("按分类分组", systemImage: "rectangle.grid.1x2")
                }
                .toggleStyle(.button)
                .help("按分类分组，共 \(filteredTemplates.count) 个模板")
            }

            ToolbarSpacer(.fixed, placement: .primaryAction)

            ToolbarItemGroup(placement: .primaryAction) {
                Button("添加分类", systemImage: "folder.badge.plus") {
                    categoryEditorRoute = TemplateCategoryEditorRoute(category: nil)
                }
                Button("新建我的模板", systemImage: "plus") {
                    templateEditorRoute = TemplateEditorRoute(template: nil)
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if filteredTemplates.isEmpty {
            ContentUnavailableView {
                Label(emptyStateTitle, systemImage: "square.grid.2x2")
            } description: {
                if presentation == .embedded,
                   searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   selection.categoryAssignment != nil {
                    Text("从“全部模板”拖动模板到左侧分类。")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if groupByCategory {
            GeometryReader { proxy in
                ScrollView {
                    GlassEffectContainer(spacing: 12) {
                        LazyVStack(alignment: .leading, spacing: 20) {
                            ForEach(templateGroups) { group in
                                let templates = filteredTemplates.filter(group.includes)
                                if !templates.isEmpty {
                                    VStack(alignment: .leading, spacing: 10) {
                                        Text(group.title)
                                            .font(.headline)
                                        LazyVGrid(columns: columns, spacing: 12) {
                                            ForEach(templates) { template in
                                                templateCard(template)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    .frame(width: contentWidth(in: proxy), alignment: .topLeading)
                    .padding(contentPadding)
                }
            }
        } else {
            GeometryReader { proxy in
                let availableWidth = contentWidth(in: proxy)
                ScrollView {
                    GlassEffectContainer(spacing: 12) {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(filteredTemplates) { template in
                                templateCard(template)
                            }
                        }
                        .frame(width: ungroupedGridWidth(availableWidth: availableWidth))
                    }
                    .frame(width: availableWidth, alignment: .top)
                    .padding(contentPadding)
                }
            }
        }
    }

    private func contentWidth(in proxy: GeometryProxy) -> CGFloat {
        max(proxy.size.width - contentPadding * 2, 0)
    }

    private func ungroupedGridWidth(availableWidth: CGFloat) -> CGFloat {
        let minimumCardWidth: CGFloat = 190
        let maximumCardWidth: CGFloat = 280
        let spacing: CGFloat = 12
        let availableColumnCount = max(
            1,
            Int((availableWidth + spacing) / (minimumCardWidth + spacing))
        )
        let visibleColumnCount = min(availableColumnCount, filteredTemplates.count)
        let contentWidth = CGFloat(visibleColumnCount) * maximumCardWidth
            + CGFloat(max(visibleColumnCount - 1, 0)) * spacing
        return min(availableWidth, contentWidth)
    }

    private func templateCard(_ template: ServiceTemplateDTO) -> some View {
        TemplateLibraryCard(
            template: template,
            categoryTitle: categoryTitle(for: template),
            sourceTitle: templateSourceTitle(template.source),
            draggableID: presentation == .embedded ? template.id : nil,
            onSelect: {
                let preset = template.subscriptionPreset
                if let onSelectPreset {
                    onSelectPreset(preset)
                } else {
                    selectedPreset = preset
                }
            },
            onCopy: { templateEditorRoute = TemplateEditorRoute(template: template) },
            onEdit: { templateEditorRoute = TemplateEditorRoute(template: template) },
            onDelete: { pendingTemplateDeletion = template }
        )
    }

    private var allTemplates: [ServiceTemplateDTO] { builtinTemplates + userTemplates }

    private var builtinTemplates: [ServiceTemplateDTO] {
        (services.builtinTemplates?.templates ?? []).map { template in
            guard case .builtin(let key) = template.key,
                  let assignment = builtinCategoryAssignments[key] else {
                return template
            }
            return template.assigningCategory(assignment)
        }
    }

    private var filteredTemplates: [ServiceTemplateDTO] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return allTemplates
            .filter(selection.includes)
            .filter { template in
                query.isEmpty
                    || template.name.localizedCaseInsensitiveContains(query)
                    || template.aliases.contains { $0.localizedCaseInsensitiveContains(query) }
            }
            .sorted {
                if $0.name != $1.name {
                    return $0.name.localizedStandardCompare($1.name) == .orderedAscending
                }
                return $0.id < $1.id
            }
    }

    private var templateGroups: [TemplateGroup] {
        ServiceCategory.allCases.map(TemplateGroup.builtin)
            + customCategories.map(TemplateGroup.custom)
    }

    private var selectionTitle: String {
        switch selection {
        case .all: AppLocalization.string("全部模板")
        case .builtin: AppLocalization.string("内置模板")
        case .user: AppLocalization.string("我的模板")
        case .builtinCategory(let category): category.title
        case .customCategory(let id):
            customCategories.first { $0.id == id }?.name ?? AppLocalization.string("我的分类")
        }
    }

    private var emptyStateTitle: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "此分类暂无模板"
            : "没有匹配模板"
    }

    private func categoryTitle(for template: ServiceTemplateDTO) -> String {
        guard let id = template.customCategoryID else { return template.category.title }
        return customCategories.first { $0.id == id }?.name ?? ServiceCategory.other.title
    }

    private func templateSourceTitle(_ source: TemplateSource) -> String {
        AppLocalization.string(source == .builtin ? "内置" : "我的模板")
    }

    @MainActor
    private func reloadLibrary() async {
        if let builtinTemplateError = services.builtinTemplateError {
            error = builtinTemplateError
        }
        await reloadUserTemplates()
        await reloadCategories()
        await reloadBuiltinCategoryAssignments()
    }

    @MainActor
    private func reloadUserTemplates() async {
        guard let store = services.templateStore else {
            error = PresentedError(TemplateLibraryError.storeUnavailable, title: "无法读取模板")
            return
        }
        do {
            userTemplates = try await store.fetchAll()
        } catch {
            self.error = PresentedError(error, title: "无法读取模板")
        }
    }

    @MainActor
    private func reloadCategories() async {
        guard let store = services.templateCategoryStore else {
            error = PresentedError(TemplateLibraryError.categoryStoreUnavailable, title: "无法读取分类")
            return
        }
        do {
            customCategories = try await store.fetchAll()
        } catch {
            self.error = PresentedError(error, title: "无法读取分类")
        }
    }

    @MainActor
    private func reloadBuiltinCategoryAssignments() async {
        guard let store = services.builtinTemplateCategoryStore else {
            error = PresentedError(
                TemplateLibraryError.categoryStoreUnavailable,
                title: "无法读取内置模板分类"
            )
            return
        }
        do {
            builtinCategoryAssignments = try await store.fetchAssignments()
        } catch {
            self.error = PresentedError(error, title: "无法读取内置模板分类")
        }
    }

    private func moveTemplate(id: String, to selection: TemplateLibrarySelection) -> Bool {
        guard let assignment = selection.categoryAssignment,
              let template = allTemplates.first(where: { $0.id == id }) else {
            return false
        }

        Task { @MainActor in
            do {
                switch template.key {
                case .builtin(let key):
                    guard let store = services.builtinTemplateCategoryStore else {
                        throw TemplateLibraryError.categoryStoreUnavailable
                    }
                    try await store.assign(
                        assignment,
                        toBuiltinTemplate: key
                    )
                case .user(let id):
                    guard let store = services.templateStore else {
                        throw TemplateLibraryError.storeUnavailable
                    }
                    try await store.save(categoryUpdateInput(
                        for: template,
                        id: id,
                        assignment: assignment
                    ))
                }
                services.notifyTemplateDataChanged()
                await reloadLibrary()
            } catch {
                self.error = PresentedError(error, title: "无法移动模板")
            }
        }
        return true
    }

    private func categoryUpdateInput(
        for template: ServiceTemplateDTO,
        id: UUID,
        assignment: TemplateCategoryAssignment
    ) -> ServiceTemplateInput {
        ServiceTemplateInput(
            id: id,
            expectedRevision: template.revision,
            name: template.name,
            aliases: template.aliases,
            category: assignment.category,
            customCategoryID: assignment.customCategoryID,
            symbolName: template.symbolName,
            iconResourceName: template.iconResourceName,
            iconURLString: template.iconURLString,
            suggestedBillingKind: template.suggestedBillingKind,
            suggestedCycleMonths: template.suggestedCycleMonths,
            suggestedMoney: template.suggestedMoney,
            currency: template.currency
        )
    }

    private func delete(_ template: ServiceTemplateDTO) {
        guard case .user(let id) = template.key,
              let revision = template.revision,
              let store = services.templateStore else { return }
        Task { @MainActor in
            do {
                try await store.delete(id: id, expectedRevision: revision)
                services.notifyTemplateDataChanged()
                await reloadUserTemplates()
            } catch {
                self.error = PresentedError(error, title: "无法删除模板")
            }
        }
    }

    private func delete(_ category: TemplateCategoryDTO) {
        guard let store = services.templateCategoryStore else { return }
        Task { @MainActor in
            do {
                try await store.delete(id: category.id, expectedRevision: category.revision)
                services.notifyTemplateDataChanged()
                if selection == .customCategory(category.id) { selection = .all }
                await reloadLibrary()
            } catch {
                self.error = PresentedError(error, title: "无法删除分类")
            }
        }
    }
}
