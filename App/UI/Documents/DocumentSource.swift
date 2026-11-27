import Foundation
import TomafocoDomain
import TomafocoApplication

/// Cabeçalho da janela de documento: título do dono e uma linha de contexto opcional
/// ("↳ Pai" da subtarefa, ícone/nome do projeto).
struct DocumentHeader: Equatable {
    var title: String
    var subtitle: String?
    var subtitleSymbol: String = "arrow.turn.down.right"
}

/// Resultado de uma gravação, no vocabulário da janela.
struct DocumentSaveOutcome: Equatable {
    enum Kind: Equatable {
        /// Gravado agora.
        case saved(Date)
        /// Nada gravado que mereça "Salvo às…" (texto igual; ou documento da tarefa apagado por
        /// ficar em branco).
        case cleared
        /// O dono (tarefa, projeto ou o próprio documento) foi apagado — nada gravado.
        case ownerMissing
    }

    let kind: Kind
    /// Outras telas precisam reler (selo "Doc" da tarefa, lista de documentos do projeto).
    let presenceChanged: Bool
}

/// O que a janela de documento (`DocumentViewModel`) precisa saber do dono do texto. A janela é
/// a mesma para o documento da tarefa (FEAT-007, 0 ou 1 por tarefa) e para os documentos do
/// projeto (FEAT-009, vários, com título editável).
@MainActor
protocol DocumentSource: AnyObject {
    /// Chave de identidade da janela (id da tarefa ou do documento do projeto).
    var id: UUID { get }
    /// Faixa exibida quando o dono some com a janela aberta.
    var missingMessage: String { get }
    /// O título do cabeçalho é editável (documento de projeto).
    var canRename: Bool { get }
    /// Texto salvo e quando; `nil` = ainda não existe (documento de tarefa novo).
    func load() throws -> (markdown: String, updatedAt: Date)?
    /// Cabeçalho atual; `nil` = dono apagado. Erro = não deu para ler (NÃO é "apagado").
    func header() throws -> DocumentHeader?
    func save(_ markdown: String) throws -> DocumentSaveOutcome
    /// Renomeia (só quando `canRename`); devolve o cabeçalho novo, `nil` se o dono sumiu.
    func rename(_ title: String) throws -> DocumentHeader?
}

extension DocumentSource {
    var canRename: Bool { false }
    func rename(_ title: String) throws -> DocumentHeader? { try header() }
}

// MARK: - Documento da tarefa (FEAT-007)

@MainActor
final class TaskDocumentSource: DocumentSource {
    let id: UUID
    private let documents: ManageTaskDocumentsUseCase
    private let tasks: ManageTasksUseCase

    init(taskID: UUID, documents: ManageTaskDocumentsUseCase, tasks: ManageTasksUseCase) {
        self.id = taskID
        self.documents = documents
        self.tasks = tasks
    }

    var missingMessage: String { "A tarefa foi apagada. O documento está só para leitura e não será salvo." }

    func load() throws -> (markdown: String, updatedAt: Date)? {
        try documents.document(taskID: id).map { ($0.markdown, $0.updatedAt) }
    }

    func header() throws -> DocumentHeader? {
        let all = try tasks.allTasks()
        guard let task = all.first(where: { $0.id == id }) else { return nil }
        return DocumentHeader(title: task.displayTitle, subtitle: TaskTree.parent(of: task, in: all)?.title)
    }

    func save(_ markdown: String) throws -> DocumentSaveOutcome {
        let result = try documents.save(taskID: id, markdown: markdown)
        switch result {
        case .saved(let document, _):
            return DocumentSaveOutcome(kind: .saved(document.updatedAt), presenceChanged: result.changesPresence)
        case .deleted, .unchanged:
            return DocumentSaveOutcome(kind: .cleared, presenceChanged: result.changesPresence)
        case .taskNotFound:
            return DocumentSaveOutcome(kind: .ownerMissing, presenceChanged: false)
        }
    }
}

// MARK: - Documento do projeto (FEAT-009)

@MainActor
final class ProjectDocumentSource: DocumentSource {
    let id: UUID
    private let documents: ManageProjectDocumentsUseCase
    private let projects: ManageProjectsUseCase

    init(documentID: UUID, documents: ManageProjectDocumentsUseCase, projects: ManageProjectsUseCase) {
        self.id = documentID
        self.documents = documents
        self.projects = projects
    }

    var missingMessage: String {
        "O documento (ou o projeto dele) foi apagado. O texto está só para leitura e não será salvo."
    }

    var canRename: Bool { true }

    func load() throws -> (markdown: String, updatedAt: Date)? {
        try documents.document(id: id).map { ($0.markdown, $0.updatedAt) }
    }

    func header() throws -> DocumentHeader? {
        guard let document = try documents.document(id: id),
              let project = try projects.allProjects().first(where: { $0.id == document.projectID }) else { return nil }
        return DocumentHeader(title: document.title, subtitle: project.title, subtitleSymbol: project.symbolName)
    }

    func save(_ markdown: String) throws -> DocumentSaveOutcome {
        switch try documents.save(id: id, markdown: markdown) {
        case .saved(let updatedAt):
            // A lista de documentos do projeto mostra "atualizado em" — avisa para reler.
            return DocumentSaveOutcome(kind: .saved(updatedAt), presenceChanged: true)
        case .unchanged:
            return DocumentSaveOutcome(kind: .cleared, presenceChanged: false)
        case .documentNotFound:
            return DocumentSaveOutcome(kind: .ownerMissing, presenceChanged: false)
        }
    }

    func rename(_ title: String) throws -> DocumentHeader? {
        guard try documents.rename(id: id, title: title) != nil else { return nil }
        return try header()
    }
}
