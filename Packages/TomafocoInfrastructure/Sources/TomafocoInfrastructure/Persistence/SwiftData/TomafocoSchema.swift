import Foundation
import SwiftData

// Esquema do banco (FEAT-006, ADR-11).
//
// Cada linha guarda a entidade do Domain inteira em `payload` (JSON do próprio `Codable` do
// Domain, com o decode tolerante de sempre) + as colunas que o banco precisa para buscar/ordenar.
// Assim o Domain continua puro, o mapeamento não perde campo nenhum e **campo novo no Domain não
// exige migração de esquema** — só mudança de coluna exige uma V2 com estágio explícito no
// `TomafocoMigrationPlan`. Mudar um `@Model` sem nova versão pode impedir o store de abrir.

public enum TomafocoSchemaV1: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        [TaskRecord.self, ProjectRecord.self, SessionHistoryRecord.self, SingletonRecord.self, TagRecord.self]
    }

    /// Tarefa (`FocusTask`). `position` preserva a ordem de inserção — a mesma do array que o
    /// `tasks.json` guardava.
    @Model
    public final class TaskRecord {
        @Attribute(.unique) public var id: UUID
        public var position: Int
        public var createdAt: Date
        public var completedAt: Date?
        public var dueDate: Date?
        public var parentID: UUID?
        public var payload: Data

        public init(id: UUID, position: Int, createdAt: Date, completedAt: Date?, dueDate: Date?,
                    parentID: UUID?, payload: Data) {
            self.id = id
            self.position = position
            self.createdAt = createdAt
            self.completedAt = completedAt
            self.dueDate = dueDate
            self.parentID = parentID
            self.payload = payload
        }
    }

    /// Projeto (FEAT-006).
    @Model
    public final class ProjectRecord {
        @Attribute(.unique) public var id: UUID
        public var title: String
        public var payload: Data

        public init(id: UUID, title: String, payload: Data) {
            self.id = id
            self.title = title
            self.payload = payload
        }
    }

    /// Uma linha do histórico de sessões (`SessionRecord`). Só insere — nunca lê o histórico
    /// inteiro para acrescentar (o `history.json` fazia isso a cada fim de etapa).
    @Model
    public final class SessionHistoryRecord {
        public var sequence: Int
        public var startedAt: Date
        public var endedAt: Date
        public var payload: Data

        public init(sequence: Int, startedAt: Date, endedAt: Date, payload: Data) {
            self.sequence = sequence
            self.startedAt = startedAt
            self.endedAt = endedAt
            self.payload = payload
        }
    }

    /// Valores únicos do app, por chave (`SingletonKey`): sessão ativa (failsafe), quadro
    /// Kanban e metadados do banco.
    @Model
    public final class SingletonRecord {
        @Attribute(.unique) public var key: String
        public var payload: Data

        public init(key: String, payload: Data) {
            self.key = key
            self.payload = payload
        }
    }

    /// Catálogo de tags (RF-09.5). `position` preserva a ordem do catálogo.
    @Model
    public final class TagRecord {
        @Attribute(.unique) public var name: String
        public var position: Int

        public init(name: String, position: Int) {
            self.name = name
            self.position = position
        }
    }
}

public typealias TaskRecord = TomafocoSchemaV1.TaskRecord
public typealias ProjectRecord = TomafocoSchemaV1.ProjectRecord
public typealias SessionHistoryRecord = TomafocoSchemaV1.SessionHistoryRecord
public typealias SingletonRecord = TomafocoSchemaV1.SingletonRecord
public typealias TagRecord = TomafocoSchemaV1.TagRecord

/// Chaves do `SingletonRecord`.
enum SingletonKey {
    static let activeSession = "activeSession"
    static let kanbanBoard = "kanbanBoard"
    static let storeMeta = "storeMeta"
}

/// Plano de migração do esquema. Vazio na V1; cada versão nova entra aqui com seu estágio.
public enum TomafocoMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] { [TomafocoSchemaV1.self] }
    public static var stages: [MigrationStage] { [] }
}
