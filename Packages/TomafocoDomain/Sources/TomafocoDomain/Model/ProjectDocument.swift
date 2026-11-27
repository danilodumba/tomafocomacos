import Foundation

/// Documento em markdown de um projeto (FEAT-009 / RF-09.20). Diferente do documento da tarefa
/// (`TaskDocument`, 0 ou 1 por tarefa), um projeto tem **vários**, cada um com título próprio —
/// especificação, ata, referências… Mesmo editor e mesmo limite de tamanho.
///
/// Documento em branco **continua existindo** (tem título e é criado de propósito pelo usuário);
/// só sai quando apagado — ao contrário do da tarefa, que some quando o texto fica vazio.
public struct ProjectDocument: Equatable, Codable, Sendable, Identifiable {
    public static let defaultTitle = "Sem título"

    public let id: UUID
    public let projectID: UUID
    public var title: String
    /// Markdown como o usuário digitou — sem trim (espaço/recuo têm significado).
    public var markdown: String
    public let createdAt: Date
    /// Última gravação do texto ou do título. Injetada pelo use case.
    public var updatedAt: Date

    public init(id: UUID, projectID: UUID, title: String, markdown: String = "",
                createdAt: Date, updatedAt: Date) {
        self.id = id
        self.projectID = projectID
        self.title = Self.normalizedTitle(title)
        self.markdown = markdown
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var summary: ProjectDocumentSummary {
        ProjectDocumentSummary(id: id, projectID: projectID, title: title, createdAt: createdAt, updatedAt: updatedAt)
    }

    /// Trim; vazio vira "Sem título" (o título não é obrigatório para criar).
    public static func normalizedTitle(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? defaultTitle : trimmed
    }

    /// Mesmo limite do documento da tarefa (`TaskDocument.maxByteCount`). Em branco é válido.
    /// - Throws: `DomainError.documentTooLarge`.
    public static func validateSize(_ markdown: String) throws {
        guard markdown.utf8.count <= TaskDocument.maxByteCount else {
            throw DomainError.documentTooLarge(maxBytes: TaskDocument.maxByteCount)
        }
    }
}

/// Linha da lista de documentos do projeto — sem o texto, que só a janela do documento lê.
public struct ProjectDocumentSummary: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let projectID: UUID
    public let title: String
    public let createdAt: Date
    public let updatedAt: Date

    public init(id: UUID, projectID: UUID, title: String, createdAt: Date, updatedAt: Date) {
        self.id = id
        self.projectID = projectID
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
