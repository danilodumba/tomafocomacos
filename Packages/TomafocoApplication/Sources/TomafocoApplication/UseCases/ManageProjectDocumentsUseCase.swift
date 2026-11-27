import Foundation
import TomafocoDomain

/// Resultado do autosave do documento do projeto — a janela usa para o status ("Salvo às…").
public enum ProjectDocumentSaveResult: Equatable, Sendable {
    case saved(updatedAt: Date)
    /// Texto igual ao salvo — nada gravado, `updatedAt` intacto.
    case unchanged
    /// Documento (ou o projeto dele) apagado com a janela aberta — nada gravado.
    case documentNotFound
}

/// Documentos em markdown dos projetos (FEAT-009 / RF-09.20): vários por projeto, com título.
/// Apagar o projeto apaga os documentos (`ManageProjectsUseCase.deleteProject`).
@MainActor
public final class ManageProjectDocumentsUseCase {
    private let documents: ProjectDocumentRepository
    private let projects: ProjectRepository
    private let now: () -> Date
    private let makeID: () -> UUID

    // `now` sem default de propósito: `Date()` é proibido na Application.
    public init(documents: ProjectDocumentRepository, projects: ProjectRepository,
                now: @escaping () -> Date, makeID: @escaping () -> UUID = { UUID() }) {
        self.documents = documents
        self.projects = projects
        self.now = now
        self.makeID = makeID
    }

    /// Documentos do projeto por título (ordem "natural" do Finder); empate → mais antigo primeiro.
    public func documents(projectID: UUID) throws -> [ProjectDocumentSummary] {
        try documents.summaries(projectID: projectID).sorted {
            let order = $0.title.localizedStandardCompare($1.title)
            return order == .orderedSame ? $0.createdAt < $1.createdAt : order == .orderedAscending
        }
    }

    public func document(id: UUID) throws -> ProjectDocument? {
        try documents.document(id: id)
    }

    /// Cria um documento vazio. Título em branco vira "Sem título". Projeto inexistente →
    /// `projectNotFound`. Títulos podem repetir (são documentos, não chaves).
    @discardableResult
    public func create(projectID: UUID, title: String) throws -> ProjectDocument {
        guard try projects.project(id: projectID) != nil else { throw DomainError.projectNotFound }
        let date = now()
        let document = ProjectDocument(id: makeID(), projectID: projectID, title: title,
                                       createdAt: date, updatedAt: date)
        try documents.save(document)
        return document
    }

    /// Renomeia. Mesmo título (após normalizar) não grava. Inexistente → `nil`.
    @discardableResult
    public func rename(id: UUID, title: String) throws -> ProjectDocument? {
        guard var document = try documents.document(id: id) else { return nil }
        let normalized = ProjectDocument.normalizedTitle(title)
        guard normalized != document.title else { return document }
        document.title = normalized
        document.updatedAt = now()
        try documents.save(document)
        return document
    }

    /// Autosave da janela. Em branco é válido (o documento continua existindo).
    /// - Throws: `DomainError.documentTooLarge` acima do limite.
    @discardableResult
    public func save(id: UUID, markdown: String) throws -> ProjectDocumentSaveResult {
        try ProjectDocument.validateSize(markdown)
        guard var document = try documents.document(id: id),
              try projects.project(id: document.projectID) != nil else { return .documentNotFound }
        guard document.markdown != markdown else { return .unchanged }
        document.markdown = markdown
        document.updatedAt = now()
        try documents.save(document)
        return .saved(updatedAt: document.updatedAt)
    }

    public func delete(id: UUID) throws {
        try documents.delete(id: id)
    }
}
