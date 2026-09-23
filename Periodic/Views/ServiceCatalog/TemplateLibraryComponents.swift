import SwiftUI

struct TemplateLibrarySidebar: View {
    @Binding var selection: TemplateLibrarySelection

    let allTemplates: [ServiceTemplateDTO]
    let builtinTemplates: [ServiceTemplateDTO]
    let userTemplates: [ServiceTemplateDTO]
    let customCategories: [TemplateCategoryDTO]
    let onEditCategory: (TemplateCategoryDTO) -> Void
    let onDeleteCategory: (TemplateCategoryDTO) -> Void
    let onMoveTemplate: (String, TemplateLibrarySelection) -> Bool

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
                        count: allTemplates.count { $0.customCategoryID == category.id },
                        selection: .customCategory(category.id)
                    )
                    .contextMenu {
                        Button("重命名") { onEditCategory(category) }
                        Button("删除分类", role: .destructive) { onDeleteCategory(category) }
                    }
                }

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
        .dropDestination(for: String.self) { templateIDs, _ in
            guard selection.categoryAssignment != nil,
                  let templateID = templateIDs.first else {
                return false
            }
            return onMoveTemplate(templateID, selection)
        }
    }
}

struct TemplateLibraryCard: View {
    let template: ServiceTemplateDTO
    let categoryTitle: String
    let sourceTitle: String
    let draggableID: String?
    let onSelect: () -> Void
    let onCopy: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        if let draggableID {
            card.draggable(draggableID)
        } else {
            card
        }
    }

    private var card: some View {
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
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .help("使用“\(template.name)”新建订阅")
        .accessibilityLabel("使用“\(template.name)”新建订阅")
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
