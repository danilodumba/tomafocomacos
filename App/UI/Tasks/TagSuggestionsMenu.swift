import SwiftUI

/// Autocomplete simples de tags: menu com as tags já conhecidas; clicar acrescenta ao campo
/// de texto (vírgula) sem duplicar. Serve criação, edição e criação em lote.
struct TagSuggestionsMenu: View {
    let knownTags: [String]
    @Binding var text: String

    var body: some View {
        Menu {
            if knownTags.isEmpty {
                Text("Nenhuma tag ainda")
            } else {
                ForEach(knownTags, id: \.self) { tag in
                    Button(tag) { append(tag) }
                }
            }
        } label: {
            Image(systemName: "tag")
        }
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Adicionar uma tag existente")
    }

    /// Acrescenta a tag ao texto (evitando duplicar), respeitando vírgulas.
    private func append(_ tag: String) {
        let existing = TasksViewModel.parseTags(text)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard !existing.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) else { return }
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        text = trimmed.isEmpty ? tag : trimmed + ", " + tag
    }
}
