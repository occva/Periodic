import Foundation

struct BuiltinTemplateCatalog: Sendable {
    enum CatalogError: LocalizedError {
        case resourceMissing

        var errorDescription: String? {
            "内置服务模板目录缺失，请重新安装应用。"
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
        return BuiltinTemplateCatalog(
            version: catalog.catalogVersion,
            templates: catalog.entries.map(\.dto)
        )
    }
}
