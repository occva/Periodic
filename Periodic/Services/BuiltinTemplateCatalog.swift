import Foundation

struct BuiltinTemplateCatalog: Sendable {
    enum CatalogError: LocalizedError {
        case resourceMissing
        case iconResourceMissing(String)

        var errorDescription: String? {
            switch self {
            case .resourceMissing:
                "内置服务模板目录缺失，请重新安装应用。"
            case .iconResourceMissing(let name):
                "内置服务模板“\(name)”的图标资源缺失，请重新安装应用。"
            }
        }
    }

    let version: String
    let templates: [ServiceTemplateDTO]

    static func load(bundle: Bundle = .main) throws -> BuiltinTemplateCatalog {
        guard let url = bundle.url(forResource: "BuiltinServiceCatalog", withExtension: "json") else {
            throw CatalogError.resourceMissing
        }
        let data = try Data(contentsOf: url)
        let catalog = try JSONDecoder().decode(BuiltinServiceCatalog.self, from: data)
        for entry in catalog.entries where iconURL(named: entry.iconResourceName, bundle: bundle) == nil {
            throw CatalogError.iconResourceMissing(entry.name)
        }
        return BuiltinTemplateCatalog(
            version: catalog.catalogVersion,
            templates: catalog.entries.map(\.dto)
        )
    }

    private static func iconURL(named resourceName: String, bundle: Bundle) -> URL? {
        let resource = resourceName as NSString
        let basename = resource.deletingPathExtension
        let fileExtension = resource.pathExtension
        return bundle.url(
            forResource: basename,
            withExtension: fileExtension,
            subdirectory: "BuiltinTemplateIcons"
        ) ?? bundle.url(forResource: basename, withExtension: fileExtension)
    }
}
