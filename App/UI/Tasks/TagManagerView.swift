import SwiftUI

/// Gestão do catálogo de tags (item 1): criar, renomear e excluir tags — reaproveitadas nas
/// tarefas. Opera sobre o `ManageTasksUseCase` via `TasksViewModel`.
struct TagManagerView: View {
    @ObservedObject var viewModel: TasksViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var newTag = ""
    /// Tag em renomeação → texto editável.
    @State private var renaming: String?
    @State private var renameText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tags")
                .font(.system(size: 15, weight: .semibold))

            HStack(spacing: 8) {
                TextField("Nova tag", text: $newTag)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(create)
                Button("Criar", action: create)
                    .disabled(newTag.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if viewModel.knownTags.isEmpty {
                Text("Nenhuma tag cadastrada.")
                    .font(.system(size: 12))
                    .foregroundStyle(Brand.textFaint)
                    .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                List(viewModel.knownTags, id: \.self) { tag in
                    tagRow(tag)
                }
                .frame(minHeight: 220)
                .scrollContentBackground(.hidden)
            }

            HStack {
                Spacer()
                Button("Fechar") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 380, height: 380)
    }

    private func tagRow(_ tag: String) -> some View {
        HStack(spacing: 8) {
            if renaming == tag {
                TextField("Nome", text: $renameText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { commitRename(tag) }
                Button("Salvar") { commitRename(tag) }
                Button("Cancelar") { renaming = nil }
            } else {
                Text(tag)
                    .foregroundStyle(Brand.textPrimary)
                Text("\(viewModel.taskCount(forTag: tag))")
                    .font(.system(size: 10))
                    .foregroundStyle(Brand.textFaint)
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(Brand.surface, in: Capsule())
                Spacer()
                Button {
                    renameText = tag
                    renaming = tag
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.plain)
                .foregroundStyle(Brand.textFaint)
                .accessibilityLabel("Renomear tag")

                Button(role: .destructive) {
                    viewModel.deleteTag(tag)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .foregroundStyle(Brand.textFaint)
                .accessibilityLabel("Apagar tag")
            }
        }
        .padding(.vertical, 2)
    }

    private func create() {
        let trimmed = newTag.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        viewModel.createTag(trimmed)
        newTag = ""
    }

    private func commitRename(_ old: String) {
        let trimmed = renameText.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty, trimmed.caseInsensitiveCompare(old) != .orderedSame {
            viewModel.renameTag(from: old, to: trimmed)
        }
        renaming = nil
    }
}
