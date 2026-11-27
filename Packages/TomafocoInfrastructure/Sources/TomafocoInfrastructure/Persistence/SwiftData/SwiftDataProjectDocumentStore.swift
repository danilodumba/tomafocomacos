import Foundation
import os
import SwiftData
import TomafocoDomain

/// `ProjectDocumentRepository` sobre o banco (FEAT-009, tabela `ProjectDocumentRecord` da V3).
/// A lista lê só as colunas (título/datas) — o texto, um documento por vez.
@MainActor
public final class SwiftDataProjectDocumentStore: ProjectDocumentRepository {

    private let database: TomafocoDatabase
    private static let logger = Logger(subsystem: "com.dsdumba.tomafoco", category: "SwiftDataProjectDocumentStore")

    public init(database: TomafocoDatabase) {
        self.database = database
    }

    public func summaries(projectID: UUID) throws -> [ProjectDocumentSummary] {
        var descriptor = FetchDescriptor<ProjectDocumentRecord>(predicate: #Predicate { $0.projectID == projectID })
        descriptor.propertiesToFetch = [\.id, \.projectID, \.title, \.createdAt, \.updatedAt]
        return try database.context.fetch(descriptor).map {
            ProjectDocumentSummary(id: $0.id, projectID: $0.projectID, title: $0.title,
                                   createdAt: $0.createdAt, updatedAt: $0.updatedAt)
        }
    }

    public func document(id: UUID) throws -> ProjectDocument? {
        guard let record = try record(id: id) else { return nil }
        return try PayloadCoding.decoder.decode(ProjectDocument.self, from: record.payload)
    }

    public func save(_ document: ProjectDocument) throws {
        // Codifica antes de tocar o contexto: erro aqui não deixa mudança pela metade pendente.
        let payload = try PayloadCoding.encoder.encode(document)
        if let record = try record(id: document.id) {
            record.title = document.title
            record.updatedAt = document.updatedAt
            record.payload = payload
        } else {
            database.context.insert(ProjectDocumentRecord(
                id: document.id, projectID: document.projectID, title: document.title,
                createdAt: document.createdAt, updatedAt: document.updatedAt, payload: payload))
        }
        try database.commit()
    }

    public func delete(id: UUID) throws {
        guard let record = try record(id: id) else { return }
        database.context.delete(record)
        try database.commit()
    }

    public func delete(projectID: UUID) throws {
        let records = try database.context.fetch(FetchDescriptor<ProjectDocumentRecord>(
            predicate: #Predicate { $0.projectID == projectID }))
        guard !records.isEmpty else { return }
        for record in records { database.context.delete(record) }
        try database.commit()
    }

    /// Apaga documentos de projetos que não existem mais — rede de segurança rodada no lançamento,
    /// como a dos documentos das tarefas. "Existe" = tem **linha** em `ProjectRecord`, legível ou não.
    /// - Returns: quantos documentos foram apagados.
    @discardableResult
    public func deleteOrphans() throws -> Int {
        var projectDescriptor = FetchDescriptor<ProjectRecord>()
        projectDescriptor.propertiesToFetch = [\.id]
        let existing = Set(try database.context.fetch(projectDescriptor).map(\.id))
        var descriptor = FetchDescriptor<ProjectDocumentRecord>()
        descriptor.propertiesToFetch = [\.id, \.projectID]
        let orphans = try database.context.fetch(descriptor).filter { !existing.contains($0.projectID) }
        guard !orphans.isEmpty else { return 0 }
        for record in orphans { database.context.delete(record) }
        try database.commit()
        Self.logger.notice("\(orphans.count, privacy: .public) documento(s) de projeto órfão(s) apagado(s)")
        return orphans.count
    }

    private func record(id: UUID) throws -> ProjectDocumentRecord? {
        var descriptor = FetchDescriptor<ProjectDocumentRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try database.context.fetch(descriptor).first
    }
}
