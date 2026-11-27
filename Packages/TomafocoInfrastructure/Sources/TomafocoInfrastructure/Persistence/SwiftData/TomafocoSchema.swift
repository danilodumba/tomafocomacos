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

/// V2 (FEAT-007, ADR-12): acrescenta a tabela de documentos das tarefas. Os modelos da V1 seguem
/// **os mesmos tipos** (não mudaram) — só a tabela nova entra, por isso o estágio é leve.
public enum TomafocoSchemaV2: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        TomafocoSchemaV1.models + [TaskDocumentRecord.self]
    }

    /// Documento em markdown de uma tarefa (`TaskDocument`). Uma linha por tarefa. O texto vai no
    /// payload como tudo no banco; `updatedAt` fica de coluna para ordenação/diagnóstico.
    @Model
    public final class TaskDocumentRecord {
        @Attribute(.unique) public var taskID: UUID
        public var updatedAt: Date
        public var payload: Data

        public init(taskID: UUID, updatedAt: Date, payload: Data) {
            self.taskID = taskID
            self.updatedAt = updatedAt
            self.payload = payload
        }
    }
}

/// V3 (FEAT-009): acrescenta a tabela de documentos dos projetos. V1 e V2 seguem **os mesmos
/// tipos** (não mudaram) — só a tabela nova entra, então o estágio é leve, como o V1 → V2.
///
/// ⚠️ Regra (ADR-11/FEAT-007): quando uma versão futura MUDAR um modelo existente, congelar cópias
/// das classes antigas em cada versão anterior — senão o hash dessas versões muda e um banco
/// antigo deixa de ser reconhecido (cai no `.bak`).
public enum TomafocoSchemaV3: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(3, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        TomafocoSchemaV2.models + [ProjectDocumentRecord.self]
    }

    /// Documento em markdown de um projeto (`ProjectDocument`). Vários por projeto. Título e datas
    /// ficam de coluna para listar sem decodificar o texto.
    @Model
    public final class ProjectDocumentRecord {
        @Attribute(.unique) public var id: UUID
        public var projectID: UUID
        public var title: String
        public var createdAt: Date
        public var updatedAt: Date
        public var payload: Data

        public init(id: UUID, projectID: UUID, title: String, createdAt: Date, updatedAt: Date, payload: Data) {
            self.id = id
            self.projectID = projectID
            self.title = title
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.payload = payload
        }
    }
}

public typealias TaskRecord = TomafocoSchemaV1.TaskRecord
public typealias ProjectRecord = TomafocoSchemaV1.ProjectRecord
public typealias SessionHistoryRecord = TomafocoSchemaV1.SessionHistoryRecord
public typealias SingletonRecord = TomafocoSchemaV1.SingletonRecord
public typealias TagRecord = TomafocoSchemaV1.TagRecord
public typealias TaskDocumentRecord = TomafocoSchemaV2.TaskDocumentRecord
public typealias ProjectDocumentRecord = TomafocoSchemaV3.ProjectDocumentRecord

/// Chaves do `SingletonRecord`.
enum SingletonKey {
    static let activeSession = "activeSession"
    /// Quadro único (FEAT-005, até a FEAT-008) — só lido, para migrar para `kanbanBoards`.
    static let kanbanBoard = "kanbanBoard"
    /// Lista de quadros (FEAT-008).
    static let kanbanBoards = "kanbanBoards"
    static let storeMeta = "storeMeta"
}

/// Plano de migração do esquema. Cada versão nova entra aqui com seu estágio; a última da lista
/// é a que o app abre (`TomafocoDatabase.currentSchema`).
public enum TomafocoMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] {
        [TomafocoSchemaV1.self, TomafocoSchemaV2.self, TomafocoSchemaV3.self]
    }
    public static var stages: [MigrationStage] { [migrateV1toV2, migrateV2toV3] }

    /// Só acrescenta a tabela de documentos: nenhuma linha existente muda.
    static let migrateV1toV2 = MigrationStage.lightweight(fromVersion: TomafocoSchemaV1.self,
                                                          toVersion: TomafocoSchemaV2.self)

    /// Só acrescenta a tabela de documentos dos projetos (FEAT-009).
    static let migrateV2toV3 = MigrationStage.lightweight(fromVersion: TomafocoSchemaV2.self,
                                                          toVersion: TomafocoSchemaV3.self)
}
