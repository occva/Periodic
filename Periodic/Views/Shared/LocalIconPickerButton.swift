import SwiftUI
import UniformTypeIdentifiers

struct LocalIconPickerButton: View {
    @Environment(AppServices.self) private var services

    let onSelect: (String) -> Void

    @State private var isPresentingFileImporter = false
    @State private var isImporting = false
    @State private var error: PresentedError?

    var body: some View {
        Button("本地图片…") {
            isPresentingFileImporter = true
        }
        .disabled(isImporting)
        .fileImporter(
            isPresented: $isPresentingFileImporter,
            allowedContentTypes: [.png, .jpeg],
            allowsMultipleSelection: false
        ) { result in
            handleFileSelection(result)
        }
        .errorAlert($error)
        .accessibilityIdentifier("choose-local-icon")
    }

    private func handleFileSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            importImage(url)
        case .failure(let selectionError):
            error = PresentedError(selectionError, title: "无法选择本地图片")
        }
    }

    private func importImage(_ url: URL) {
        isImporting = true
        Task { @MainActor in
            do {
                let reference = try await services.appleIconCache.persistLocalImage(from: url)
                onSelect(reference)
                error = nil
            } catch {
                self.error = PresentedError(error, title: "无法使用所选图片")
            }
            isImporting = false
        }
    }
}
