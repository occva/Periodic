import SwiftUI

struct TemplateLibrarySidebar: View {
    @Binding var selection: TemplateLibrarySelection

    let allTemplates: [ServiceTemplateDTO]
    let builtinTemplates: [ServiceTemplateDTO]
    let userTemplates: [ServiceTemplateDTO]
    let customCategories: [TemplateCategoryDTO]
    let onAddCategory: () -> Void
    let onEditCategory: (TemplateCategoryDTO) -> Void
    let onDeleteCategory: (TemplateCategoryDTO) -> Void
    let onAddTemplate: () -> Void

    var body: some View {
        List(selection: $selection) {
            Section("模板库") {
                sidebarRow(
                    title: "全部模板",
                    symbol: "square.grid.2x2",
                    count: allTemplates.count,
                    selection: .all
                )
                sidebarRow(
                    title: "内置模板",
                    symbol: "shippingbox.fill",
                    count: builtinTemplates.count,
                    selection: .builtin
                )
                sidebarRow(
                    title: "我的模板",
                    symbol: "person.crop.square",
                    count: userTemplates.count,
                    selection: .user
                )
            }

            Section("内置分类") {
                ForEach(ServiceCategory.allCases) { category in
                    sidebarRow(
                        title: category.title,
                        symbol: category.sidebarSymbol,
                        count: allTemplates.count {
                            $0.customCategoryID == nil && $0.category == category
                        },
                        selection: .builtinCategory(category)
                    )
                }
            }

            Section("我的分类") {
                ForEach(customCategories) { category in
                    sidebarRow(
                        title: category.name,
                        symbol: "folder",
                        count: userTemplates.count { $0.customCategoryID == category.id },
                        selection: .customCategory(category.id)
                    )
                    .contextMenu {
                        Button("重命名") { onEditCategory(category) }
                        Button("删除分类", role: .destructive) { onDeleteCategory(category) }
                    }
                }

                Button("添加分类", systemImage: "folder.badge.plus", action: onAddCategory)
                    .buttonStyle(.plain)
            }

            Section("维护") {
                Button("新建我的模板", systemImage: "plus", action: onAddTemplate)
                    .buttonStyle(.plain)
            }
        }
        .listStyle(.sidebar)
        .accessibilityIdentifier("template-library-sidebar")
    }

    private func sidebarRow(
        title: String,
        symbol: String,
        count: Int,
        selection: TemplateLibrarySelection
    ) -> some View {
        HStack(spacing: 8) {
            Label(title, systemImage: symbol)
            Spacer()
            Text("\(count)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .tag(selection)
    }
}

struct TemplateLibraryHeader: View {
    let title: String
    @Binding var searchText: String
    let showsCloseButton: Bool
    let onAddCategory: () -> Void
    let onAddTemplate: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.title2.weight(.semibold))
            Spacer()
            TextField("搜索模板名称或别名", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 280)
            Button("添加分类", systemImage: "folder.badge.plus", action: onAddCategory)
                .labelStyle(.iconOnly)
                .buttonStyle(.glass)
            Button("新建我的模板", systemImage: "plus", action: onAddTemplate)
                .labelStyle(.iconOnly)
                .buttonStyle(.glassProminent)
            if showsCloseButton {
                Button("关闭", systemImage: "xmark", action: onClose)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.glass)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .accessibilityIdentifier("template-library-header")
    }
}

struct TemplateLibraryControls: View {
    @Binding var groupByCategory: Bool
    let templateCount: Int

    var body: some View {
        HStack(spacing: 12) {
            Toggle("按分类分组", isOn: $groupByCategory)
                .toggleStyle(.button)
            Spacer()
            Text("\(templateCount) 个模板")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

struct TemplateLibraryCard: View {
    let template: ServiceTemplateDTO
    let categoryTitle: String
    let sourceTitle: String
    let onSelect: () -> Void
    let onCopy: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                ServiceIconView(
                    iconResourceName: template.iconResourceName,
                    iconURLString: template.iconURLString,
                    fallbackSeed: template.name,
                    size: 36
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(template.name)
                        .font(.headline)
                        .lineLimit(1)
                    Text("\(categoryTitle) · \(sourceTitle)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 14))
        .contextMenu {
            if template.source == .builtin {
                Button("复制为我的模板", action: onCopy)
            } else {
                Button("编辑模板", action: onEdit)
                Button("删除模板", role: .destructive, action: onDelete)
            }
        }
    }
}
