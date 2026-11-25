import Foundation
import TomafocoDomain

/// Documentos em memória — padrão do `ManageTasksUseCase` quando nenhum store é injetado (testes
/// que não tratam de documento). O app real injeta o store do banco (Infrastructure).
@MainActor
public final class EphemeralTaskDocumentRepository: TaskDocumentRepository {
    private var documents: [UUID: TaskDocument] = [:]

    public nonisolated init() {}

    public func document(taskID: UUID) throws -> TaskDocument? { documents[taskID] }
    public func save(_ document: TaskDocument) throws { documents[document.taskID] = document }
    public func delete(taskIDs: Set<UUID>) throws { taskIDs.forEach { documents[$0] = nil } }
    public func taskIDsWithDocument() throws -> Set<UUID> { Set(documents.keys) }
}

/// Transação sem banco: executa o bloco e pronto. Padrão quando nenhum `UnitOfWork` é injetado —
/// sem store transacional não há o que desfazer.
@MainActor
public final class ImmediateUnitOfWork: UnitOfWork {
    public nonisolated init() {}
    public func perform<T>(_ work: () throws -> T) throws -> T { try work() }
}
