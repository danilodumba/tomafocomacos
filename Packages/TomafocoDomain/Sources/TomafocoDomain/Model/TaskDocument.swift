import Foundation

/// Documento em markdown de uma tarefa (FEAT-007 / RF-09.17). No máximo um por tarefa —
/// `taskID` é a identidade.
///
/// Entidade **separada** da `FocusTask` de propósito (ADR-12): o texto pode ter centenas de KB e só
/// a janela do documento o usa. Dentro da tarefa ele iria junto em toda leitura da lista, do
/// Kanban, do timer e em cada comparação do espelho em memória do store.
public struct TaskDocument: Equatable, Codable, Sendable {
    public let taskID: UUID
    /// Markdown como o usuário digitou — sem trim interno (espaço/recuo têm significado).
    public let markdown: String
    /// Última gravação. Injetada pelo use case — `Date()` é proibido no Domain/Application.
    public let updatedAt: Date

    /// Limite do texto em bytes UTF-8 (P3 da FEAT-007): protege o editor e o parse a cada
    /// digitação; muito acima de qualquer documento real.
    public static let maxByteCount = 1_000_000

    public init(taskID: UUID, markdown: String, updatedAt: Date) {
        self.taskID = taskID
        self.markdown = markdown
        self.updatedAt = updatedAt
    }

    /// Texto a gravar: `nil` quando só tem espaço/quebra de linha (documento vazio = sem
    /// documento, P4); o texto **inalterado** caso contrário.
    /// - Throws: `DomainError.documentTooLarge` acima de `maxByteCount`.
    public static func validated(_ markdown: String) throws -> String? {
        guard !markdown.allSatisfy(\.isWhitespace) else { return nil }
        guard markdown.utf8.count <= maxByteCount else {
            throw DomainError.documentTooLarge(maxBytes: maxByteCount)
        }
        return markdown
    }

    /// Contagem de palavras para o resumo no formulário ("N palavras").
    public var wordCount: Int {
        markdown.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }
}
