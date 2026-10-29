import Foundation
import os
import SwiftData
import TomafocoDomain

/// `ProjectRepository` sobre o banco (FEAT-006).
@MainActor
public final class SwiftDataProjectStore: ProjectRepository {

    private let database: TomafocoDatabase
    private static let logger = Logger(subsystem: "com.dsdumba.tomafoco", category: "SwiftDataProjectStore")

    public init(database: TomafocoDatabase) {
        self.database = database
    }

    /// Projeto ilegível é pulado (e logado) — as tarefas dele aparecem sem projeto até alguém
    /// editar. Nunca é apagado por isso.
    public func loadProjects() throws -> [Project] {
        try database.context.fetch(FetchDescriptor<ProjectRecord>()).compactMap { record in
            do {
                return try PayloadCoding.decoder.decode(Project.self, from: record.payload)
            } catch {
                Self.logger.error("Projeto \(record.id, privacy: .public) ilegível: \(String(describing: error), privacy: .public)")
                return nil
            }
        }
    }

    public func project(id: UUID) throws -> Project? {
        guard let record = try record(id: id) else { return nil }
        return try PayloadCoding.decoder.decode(Project.self, from: record.payload)
    }

    public func upsert(_ project: Project) throws {
        let payload = try PayloadCoding.encoder.encode(project)
        if let record = try record(id: project.id) {
            record.title = project.title
            record.payload = payload
        } else {
            database.context.insert(ProjectRecord(id: project.id, title: project.title, payload: payload))
        }
        try database.commit()
    }

    public func delete(id: UUID) throws {
        if let record = try record(id: id) { database.context.delete(record) }
        try database.commit()
    }

    private func record(id: UUID) throws -> ProjectRecord? {
        var descriptor = FetchDescriptor<ProjectRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try database.context.fetch(descriptor).first
    }
}
