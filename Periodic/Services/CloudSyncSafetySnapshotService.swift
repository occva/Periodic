import Foundation

actor CloudSyncSafetySnapshotService {
    private let root: URL
    private let fileManager: FileManager

    init(
        root: URL,
        fileManager: FileManager = .default
    ) {
        self.root = root
        self.fileManager = fileManager
    }

    func write(
        _ package: EncodedDataPackage,
        datasetID: UUID,
        now: Date = Date()
    ) throws -> URL {
        try fileManager.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let filename = [
            "Before iCloud",
            datasetID.uuidString,
            formatter.string(from: now),
        ].joined(separator: "-") + ".periodicdata"
        let destination = root.appending(
            path: filename,
            directoryHint: .isDirectory
        )
        let wrapper = try DataPackageCodec.fileWrapper(for: package)
        try wrapper.write(
            to: destination,
            options: .atomic,
            originalContentsURL: nil
        )
        return destination
    }
}
