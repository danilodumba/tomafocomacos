import Foundation

/// Desmarca todos os itens de checklist (`- [x]` → `- [ ]`) de um markdown (FEAT-007, P2).
///
/// Usado no clone da tarefa diária: documento de diária costuma ser checklist recorrente, e o
/// clone de amanhã tem que nascer zerado. É port porque achar "o que é item de checklist" exige
/// o parser de markdown, e Domain/Application não dependem dele — a implementação real vive no
/// pacote `TomafocoMarkdown` e é injetada no Composition Root.
public protocol ChecklistResetting: Sendable {
    func uncheckingAll(_ markdown: String) -> String
}

/// Não mexe no texto — padrão quando nada é injetado (testes que não tratam de documento).
public struct IdentityChecklistResetter: ChecklistResetting {
    public init() {}
    public func uncheckingAll(_ markdown: String) -> String { markdown }
}
