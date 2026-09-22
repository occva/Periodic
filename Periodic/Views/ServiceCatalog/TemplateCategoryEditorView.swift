import SwiftUI

struct TemplateCategoryEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let category: TemplateCategoryDTO?
    let onSave: @MainActor (TemplateCategoryInput) async throws -> Void

    @State private var name: String
    @State private var isSaving = false
    @State private var error: PresentedError?

    init(
        category: TemplateCategoryDTO?,
        onSave: @escaping @MainActor (TemplateCategoryInput) async throws -> Void
    ) {
        self.category = category
        self.onSave = onSave
        _name = State(initialValue: category?.name ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(category == nil ? "添加模板分类" : "重命名模板分类")
                .font(.title2.weight(.semibold))

            TextField("分类名称", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit(save)

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(isSaving)
                    .buttonStyle(.glass)
                Button("保存", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(isSaving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .buttonStyle(.glassProminent)
            }
        }
        .padding(24)
        .frame(width: 420)
        .errorAlert($error)
    }

    private func save() {
        let input = TemplateCategoryInput(
            id: category?.id ?? UUID(),
            expectedRevision: category?.revision,
            name: name
        )
        isSaving = true
        Task { @MainActor in
            do {
                try await onSave(input)
                dismiss()
            } catch {
                self.error = PresentedError(error, title: "无法保存分类")
                isSaving = false
            }
        }
    }
}
