import SwiftUI

enum TemplateLibraryPresentation {
    case sheet
    case embedded
}

struct TemplateLibraryView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss

    let presentation: TemplateLibraryPresentation
    let onCreateSubscription: @MainActor (SubscriptionCreateInput) async throws -> Void

    @State private var userTemplates: [ServiceTemplateDTO] = []
    @State private var customCategories: [TemplateCategoryDTO] = []
    @State private var searchText = ""
    @State private var selection = TemplateLibrarySelection.all
    @State private var groupByCategory = false
    @State private var selectedPreset: SubscriptionTemplatePreset?
    @State private var templateEditorRoute: TemplateEditorRoute?
    @State private var categoryEditorRoute: TemplateCategoryEditorRoute?
    @State private var pendingTemplateDeletion: ServiceTemplateDTO?
    @State private var pendingCategoryDeletion: TemplateCategoryDTO?
    @State private var error: PresentedError?

    private let columns = [GridItem(.adaptive(minimum: 190, maximum: 280), spacing: 12)]

    var body: some View {
        NavigationStack {
            HStack(spacing: 0) {
                sidebar
                    .frame(width: 240)

                Divider()

                VStack(spacing: 0) {
                    header
                    Divider()
                    controls
                    Divider()
                    content
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .accessibilityIdentifier("template-library-content")
            }
            .navigationDestination(item: $selectedPreset) { preset in
                SubscriptionEditorView(preset: preset) { input in
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

    private var sidebar: some View {
        TemplateLibrarySidebar(
            selection: $selection,
            allTemplates: allTemplates,
            builtinTemplates: builtinTemplates,
            userTemplates: userTemplates,
            customCategories: customCategories,
            onAddCategory: {
                categoryEditorRoute = TemplateCategoryEditorRoute(category: nil)
            },
            onEditCategory: { category in
                categoryEditorRoute = TemplateCategoryEditorRoute(category: category)
            },
            onDeleteCategory: { category in
                pendingCategoryDeletion = category
            },
            onAddTemplate: {
                templateEditorRoute = TemplateEditorRoute(template: nil)
            }
        )
    }

    private var header: some View {
        TemplateLibraryHeader(
            title: selectionTitle,
            searchText: $searchText,
            showsCloseButton: presentation == .sheet,
            onAddCategory: {
                categoryEditorRoute = TemplateCategoryEditorRoute(category: nil)
            },
            onAddTemplate: {
                templateEditorRoute = TemplateEditorRoute(template: nil)
            },
            onClose: { dismiss() }
        )
    }

    private var controls: some View {
        TemplateLibraryControls(
            groupByCategory: $groupByCategory,
            templateCount: filteredTemplates.count
        )
    }

    @ViewBuilder
    private var content: some View {
        if filteredTemplates.isEmpty {
            ContentUnavailableView("没有匹配模板", systemImage: "square.grid.2x2")
        } else if groupByCategory {
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
                }
                .padding(16)
            }
        } else {
            ScrollView {
                GlassEffectContainer(spacing: 12) {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(filteredTemplates) { template in
                            templateCard(template)
                        }
                    }
                }
                .padding(16)
            }
        }
    }

    private func templateCard(_ template: ServiceTemplateDTO) -> some View {
        TemplateLibraryCard(
            template: template,
            categoryTitle: categoryTitle(for: template),
            sourceTitle: templateSourceTitle(template.source),
            onSelect: { selectedPreset = template.subscriptionPreset },
            onCopy: { templateEditorRoute = TemplateEditorRoute(template: template) },
            onEdit: { templateEditorRoute = TemplateEditorRoute(template: template) },
            onDelete: { pendingTemplateDeletion = template }
        )
    }

    private var allTemplates: [ServiceTemplateDTO] { builtinTemplates + userTemplates }

    private var builtinTemplates: [ServiceTemplateDTO] {
        services.builtinTemplates?.templates ?? []
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
