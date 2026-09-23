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
    @FocusState private var isQueryFocused: Bool

    init(initialQuery: String, onSelect: @escaping (String) -> Void) {
        _query = State(initialValue: initialQuery)
        self.onSelect = onSelect
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("选择 Apple 图标")
                    .font(.title2.weight(.semibold))

                Spacer()

                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                TextField("搜索 App Store 应用", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 260)
                    .focused($isQueryFocused)
                    .onSubmit(search)
                    .accessibilityIdentifier("apple-icon-query")

                Picker("地区", selection: $country) {
                    Text("中国").tag("cn")
                    Text("美国").tag("us")
                    Text("日本").tag("jp")
                    Text("香港").tag("hk")
                }
                .labelsHidden()
                .frame(width: 96)

                Button("搜索", systemImage: "magnifyingglass", action: search)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSearch)
                    .accessibilityIdentifier("apple-icon-search")
            }
            .padding(16)

            Divider()

            Group {
                if isSearching {
                    ProgressView("正在向 Apple 查询…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityIdentifier("apple-icon-search-progress")
                } else if results.isEmpty {
                    ContentUnavailableView {
                        Label("搜索 Apple 图标", systemImage: "apple.logo")
                    } description: {
                        Text("输入应用名称后按 Return，或点按“搜索”。")
                    }
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
        .errorAlert($error)
        .onAppear { isQueryFocused = true }
    }

    private var canSearch: Bool {
        !isSearching && !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func search() {
        guard canSearch else { return }
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
