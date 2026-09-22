import SwiftUI

struct AppleIconPickerView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss

    let onSelect: (String) -> Void

    @State private var query: String
    @State private var country = "cn"
    @State private var results: [AppleIconSearchResult] = []
    @State private var isSearching = false
    @State private var selectedResultID: Int64?
    @State private var error: PresentedError?

    init(initialQuery: String, onSelect: @escaping (String) -> Void) {
        _query = State(initialValue: initialQuery)
        self.onSelect = onSelect
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                TextField("搜索 App Store 应用", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(search)
                Picker("地区", selection: $country) {
                    Text("中国").tag("cn")
                    Text("美国").tag("us")
                    Text("日本").tag("jp")
                    Text("香港").tag("hk")
                }
                .frame(width: 110)
                Button("搜索", action: search)
                    .keyboardShortcut(.defaultAction)
                    .disabled(isSearching || query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(16)

            Divider()

            Group {
                if isSearching {
                    ProgressView("正在向 Apple 查询…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if results.isEmpty {
                    ContentUnavailableView("搜索 Apple 图标", systemImage: "apple.logo")
                } else {
                    ScrollView {
                        GlassEffectContainer(spacing: 12) {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], spacing: 12) {
                                ForEach(results) { result in
                                    Button {
                                        select(result)
                                    } label: {
                                        HStack(spacing: 10) {
                                            AsyncImage(url: result.artworkURL) { image in
                                                image.resizable().scaledToFill()
                                            } placeholder: {
                                                ProgressView().controlSize(.small)
                                            }
                                            .frame(width: 48, height: 48)
                                            .clipShape(.rect(cornerRadius: 10))

                                            VStack(alignment: .leading, spacing: 3) {
                                                Text(result.name).lineLimit(1)
                                                Text(result.artistName)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                                    .lineLimit(1)
                                            }
                                            Spacer(minLength: 0)
                                            if selectedResultID == result.id {
                                                ProgressView().controlSize(.small)
                                            }
                                        }
                                        .padding(10)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(selectedResultID != nil)
                                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 12))
                                }
                            }
                        }
                        .padding(16)
                    }
                }
            }
        }
        .frame(width: 720, height: 520, alignment: .top)
        .buttonStyle(.glass)
        .errorAlert($error)
    }

    private func search() {
        isSearching = true
        Task { @MainActor in
            do {
                results = try await services.appleIconSearch.search(term: query, country: country)
                error = nil
            } catch {
                self.error = PresentedError(error, title: "无法搜索 Apple 图标")
                results = []
            }
            isSearching = false
        }
    }

    private func select(_ result: AppleIconSearchResult) {
        selectedResultID = result.id
        Task { @MainActor in
            do {
                let reference = try await services.appleIconCache.persist(from: result.artworkURL)
                onSelect(reference)
                dismiss()
            } catch {
                self.error = PresentedError(error, title: "无法保存 Apple 图标")
                selectedResultID = nil
            }
        }
    }
}
