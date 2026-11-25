import Foundation
import os
import SwiftData
import TomafocoDomain

/// `TaskDocumentRepository` sobre o banco (FEAT-007, ADR-12).
///
/// Texto é lido **uma linha por vez** (`document(taskID:)`), nunca a tabela inteira. O conjunto
/// de tarefas com documento (selo da lista/Kanban, pedido a cada refresh das janelas) fica em
/// cache: lido uma vez com `propertiesToFetch = [taskID]` e mantido pelas gravações deste store;
/// descartado quando uma transação é desfeita.
@MainActor
public final class SwiftDataTaskDocumentStore: TaskDocumentRepository {

    private let database: TomafocoDatabase
    private var cachedIDs: Set<UUID>?
    private static let logger = Logger(subsystem: "com.dsdumba.tomafoco", category: "SwiftDataTaskDocumentStore")

    public init(database: TomafocoDatabase) {
        self.database = database
        database.onRollback { [weak self] in self?.cachedIDs = nil }
    }

    public func document(taskID: UUID) throws -> TaskDocument? {
        guard let record = try record(taskID: taskID) else { return nil }
        return try PayloadCoding.decoder.decode(TaskDocument.self, from: record.payload)
    }

    public func save(_ document: TaskDocument) throws {
        // Codifica antes de tocar o contexto: erro aqui não deixa mudança pela metade pendente.
        let payload = try PayloadCoding.encoder.encode(document)
        if let record = try record(taskID: document.taskID) {
            record.updatedAt = document.updatedAt
            record.payload = payload
        } else {
            database.context.insert(TaskDocumentRecord(taskID: document.taskID, updatedAt: document.updatedAt,
                                                       payload: payload))
        }
        cachedIDs?.insert(document.taskID)
        try database.commit()
    }

    public func delete(taskIDs: Set<UUID>) throws {
        guard !taskIDs.isEmpty else { return }
        let ids = Array(taskIDs)
        let records = try database.context.fetch(FetchDescriptor<TaskDocumentRecord>(
            predicate: #Predicate { ids.contains($0.taskID) }))
        guard !records.isEmpty else { return }
        for record in records { database.context.delete(record) }
        cachedIDs?.subtract(taskIDs)
        try database.commit()
    }

    public func taskIDsWithDocument() throws -> Set<UUID> {
        if let cachedIDs { return cachedIDs }
        var descriptor = FetchDescriptor<TaskDocumentRecord>()
        descriptor.propertiesToFetch = [\.taskID]
        let ids = Set(try database.context.fetch(descriptor).map(\.taskID))
        cachedIDs = ids
        return ids
    }

    /// Apaga documentos de tarefas que não existem mais (FEAT-007). Rede de segurança rodada no
    /// lançamento: o caminho normal (`deleteTask`) já apaga na mesma transação, mas qualquer
    /// remoção de tarefa que escape dele deixaria o texto órfão no banco para sempre.
    ///
    /// "Existe" = tem **linha** no banco, legível ou não — nunca a lista do `TaskRepository`: o
    /// `SwiftDataTaskStore` deixa fora da lista a tarefa cujo payload não decodifica (e preserva a
    /// linha), e apagar o documento dela por isso seria perda definitiva.
    /// - Returns: quantos documentos foram apagados.
    @discardableResult
    public func deleteOrphans() throws -> Int {
        var descriptor = FetchDescriptor<TaskRecord>()
        descriptor.propertiesToFetch = [\.id]
        let existingTaskIDs = Set(try database.context.fetch(descriptor).map(\.id))
        let orphans = try taskIDsWithDocument().subtracting(existingTaskIDs)
        guard !orphans.isEmpty else { return 0 }
        try delete(taskIDs: orphans)
        Self.logger.notice("\(orphans.count, privacy: .public) documento(s) órfão(s) apagado(s)")
        return orphans.count
    }

    private func record(taskID: UUID) throws -> TaskDocumentRecord? {
        var descriptor = FetchDescriptor<TaskDocumentRecord>(predicate: #Predicate { $0.taskID == taskID })
        descriptor.fetchLimit = 1
        return try database.context.fetch(descriptor).first
    }
}
