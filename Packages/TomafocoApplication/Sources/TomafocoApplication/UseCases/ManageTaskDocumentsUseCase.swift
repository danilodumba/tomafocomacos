import Foundation
import TomafocoDomain

/// Resultado de `ManageTaskDocumentsUseCase.save` — a janela do documento usa para o status
/// ("Salvo às…") e para só avisar as outras janelas quando o selo muda (documento passou a
/// existir ou deixou de existir), não a cada tecla.
public enum TaskDocumentSaveResult: Equatable, Sendable {
    /// Gravado. `created` = a tarefa não tinha documento antes.
    case saved(TaskDocument, created: Bool)
    /// Texto ficou em branco e o documento que existia foi apagado (P4 da FEAT-007).
    case deleted
    /// Nada a gravar: texto igual ao salvo, ou em branco sem documento.
    case unchanged
    /// A tarefa não existe mais (apagada com a janela do documento aberta) — nada gravado.
    case taskNotFound

    /// O selo "tem documento" mudou.
    public var changesPresence: Bool {
        switch self {
        case .saved(_, let created): return created
        case .deleted: return true
        case .unchanged, .taskNotFound: return false
        }
    }
}

/// Documento em markdown das tarefas (FEAT-007 / RF-09.17).
@MainActor
public final class ManageTaskDocumentsUseCase {
    private let documents: TaskDocumentRepository
    private let tasks: TaskRepository
    private let now: () -> Date

    // `now` sem default de propósito: `Date()` é proibido na Application.
    public init(documents: TaskDocumentRepository, tasks: TaskRepository, now: @escaping () -> Date) {
        self.documents = documents
        self.tasks = tasks
        self.now = now
    }

    public func document(taskID: UUID) throws -> TaskDocument? {
        try documents.document(taskID: taskID)
    }

    public func taskIDsWithDocument() throws -> Set<UUID> {
        try documents.taskIDsWithDocument()
    }

    /// Grava o texto da janela (autosave). Em branco apaga; igual ao salvo não regrava (nem mexe
    /// em `updatedAt`). - Throws: `DomainError.documentTooLarge` acima do limite.
    @discardableResult
    public func save(taskID: UUID, markdown: String) throws -> TaskDocumentSaveResult {
        guard try tasks.task(id: taskID) != nil else { return .taskNotFound }
        let current = try documents.document(taskID: taskID)
        guard let text = try TaskDocument.validated(markdown) else {
            guard current != nil else { return .unchanged }
            try documents.delete(taskIDs: [taskID])
            return .deleted
        }
        guard current?.markdown != text else { return .unchanged }
        let document = TaskDocument(taskID: taskID, markdown: text, updatedAt: now())
        try documents.save(document)
        return .saved(document, created: current == nil)
    }
}
