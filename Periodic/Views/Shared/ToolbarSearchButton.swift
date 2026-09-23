import SwiftUI

struct ToolbarSearchButton: View {
    @Binding var text: String

    let prompt: String

    @State private var isPresented = false
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Label("搜索", systemImage: "magnifyingglass")
        }
        .keyboardShortcut("f", modifiers: .command)
        .help("搜索（⌘F）")
        .popover(isPresented: $isPresented, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    TextField(prompt, text: $text)
                        .textFieldStyle(.roundedBorder)
                        .focused($isFieldFocused)

                    if !text.isEmpty {
                        Button("清除", systemImage: "xmark.circle.fill") {
                            text = ""
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.plain)
                        .help("清除搜索")
                    }
                }

                HStack {
                    Text("输入时即时筛选")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("关闭") { isPresented = false }
                        .keyboardShortcut(.cancelAction)
                }
            }
            .padding(12)
            .frame(width: 320)
            .onAppear { isFieldFocused = true }
        }
    }
}
