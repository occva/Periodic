import Foundation

struct TemplateEditorRoute: Identifiable, Hashable {
    let id = UUID()
    let template: ServiceTemplateDTO?
}

struct TemplateCategoryEditorRoute: Identifiable {
    let id = UUID()
    let category: TemplateCategoryDTO?
}

enum TemplateLibrarySelection: Hashable {
    case all
    case builtin
    case user
    case builtinCategory(ServiceCategory)
    case customCategory(UUID)

    func includes(_ template: ServiceTemplateDTO) -> Bool {
        switch self {
        case .all: true
        case .builtin: template.source == .builtin
        case .user: template.source == .user
        case .builtinCategory(let category):
            template.customCategoryID == nil && template.category == category
        case .customCategory(let id): template.customCategoryID == id
        }
    }

    var categoryAssignment: TemplateCategoryAssignment? {
        switch self {
        case .builtinCategory(let category): .builtin(category)
        case .customCategory(let id): .custom(id)
        case .all, .builtin, .user: nil
        }
    }
}

enum TemplateGroup: Identifiable {
    case builtin(ServiceCategory)
    case custom(TemplateCategoryDTO)

    var id: String {
        switch self {
        case .builtin(let category): "builtin.\(category.rawValue)"
        case .custom(let category): "custom.\(category.id.uuidString)"
        }
    }

    var title: String {
        switch self {
        case .builtin(let category): category.title
        case .custom(let category): category.name
        }
    }

    func includes(_ template: ServiceTemplateDTO) -> Bool {
        switch self {
        case .builtin(let category):
            template.customCategoryID == nil && template.category == category
        case .custom(let category): template.customCategoryID == category.id
        }
    }
}

extension ServiceCategory {
    var sidebarSymbol: String {
        switch self {
        case .workStudy: "briefcase"
        case .tools: "wrench.and.screwdriver"
        case .media: "play.rectangle"
        case .household: "house"
        case .communication: "antenna.radiowaves.left.and.right"
        case .food: "fork.knife"
        case .other: "ellipsis.circle"
        }
    }
}

enum TemplateLibraryError: LocalizedError {
    case storeUnavailable
    case categoryStoreUnavailable

    var errorDescription: String? {
        switch self {
        case .storeUnavailable: "模板数据库尚未就绪。"
        case .categoryStoreUnavailable: "模板分类数据库尚未就绪。"
        }
    }
}
