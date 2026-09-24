import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let periodicDataPackage = UTType(
        exportedAs: "local.lhg.periodic.data-package",
        conformingTo: .package
    )
}

struct PeriodicDataPackageDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.periodicDataPackage] }

    let package: EncodedDataPackage

    init(package: EncodedDataPackage) {
        self.package = package
    }

    init(configuration: ReadConfiguration) throws {
        package = try DataPackageCodec.encodedPackage(from: configuration.file)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        try DataPackageCodec.fileWrapper(for: package)
    }
}
