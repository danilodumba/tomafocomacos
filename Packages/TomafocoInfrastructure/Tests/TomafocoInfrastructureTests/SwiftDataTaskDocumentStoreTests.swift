import XCTest
import SwiftData
import TomafocoDomain
@testable import TomafocoInfrastructure

/// Documentos das tarefas (FEAT-007) + migração do banco V1 → V2.
@MainActor
final class SwiftDataTaskDocumentStoreTests: XCTestCase {

    private var database: TomafocoDatabase!

    override func setUp() async throws {
        database = try TomafocoDatabase.inMemory()
    }

    private func doc(_ taskID: UUID = UUID(), _ text: String = "# Oi\n\n- [ ] a", at seconds: TimeInterval = 1_000) -> TaskDocument {
        TaskDocument(taskID: taskID, markdown: text, updatedAt: Date(timeIntervalSince1970: seconds))
    }

    private struct Boom: Error {}

    func test_salvaLe_eSubstitui() throws {
        let store = SwiftDataTaskDocumentStore(database: database)
        let id = UUID()
        try store.save(doc(id, "v1"))
        try store.save(doc(id, "v2", at: 2_000))

        let fresh = SwiftDataTaskDocumentStore(database: database)
        XCTAssertEqual(try fresh.document(taskID: id), doc(id, "v2", at: 2_000))
        XCTAssertEqual(try database.context.fetch(FetchDescriptor<TaskDocumentRecord>()).count, 1)
        XCTAssertNil(try fresh.document(taskID: UUID()))
    }

    func test_taskIDsWithDocument_acompanhaGravacoes() throws {
        let store = SwiftDataTaskDocumentStore(database: database)
        let a = UUID(), b = UUID()
        XCTAssertEqual(try store.taskIDsWithDocument(), [])
        try store.save(doc(a))
        try store.save(doc(b))
        XCTAssertEqual(try store.taskIDsWithDocument(), [a, b])
        try store.delete(taskIDs: [a, UUID()])
        XCTAssertEqual(try store.taskIDsWithDocument(), [b])
        XCTAssertEqual(try SwiftDataTaskDocumentStore(database: database).taskIDsWithDocument(), [b])
    }

    func test_rollback_descartaCacheEGravacao() throws {
        let store = SwiftDataTaskDocumentStore(database: database)
        let kept = UUID(), dropped = UUID()
        try store.save(doc(kept))
        XCTAssertEqual(try store.taskIDsWithDocument(), [kept])

        XCTAssertThrowsError(try database.perform {
            try store.save(doc(dropped))
            try store.delete(taskIDs: [kept])
            throw Boom()
        })

        XCTAssertEqual(try store.taskIDsWithDocument(), [kept])
        XCTAssertNotNil(try store.document(taskID: kept))
        XCTAssertNil(try store.document(taskID: dropped))
    }

    func test_tarefaEDocumentoNaMesmaTransacao() throws {
        let tasks = SwiftDataTaskStore(database: database)
        let documents = SwiftDataTaskDocumentStore(database: database)
        let task = FocusTask(id: UUID(), title: "T", source: .manual, createdAt: Date(timeIntervalSince1970: 1))
        try tasks.saveTasks([task])
        try documents.save(doc(task.id))

        try database.perform {
            try tasks.saveTasks([])
            try documents.delete(taskIDs: [task.id])
        }
        XCTAssertEqual(try SwiftDataTaskDocumentStore(database: database).taskIDsWithDocument(), [])
    }

    func test_deleteOrphans() throws {
        let store = SwiftDataTaskDocumentStore(database: database)
        let alive = FocusTask(id: UUID(), title: "Viva", source: .manual, createdAt: Date(timeIntervalSince1970: 1))
        let orphan = UUID()
        try SwiftDataTaskStore(database: database).saveTasks([alive])
        try store.save(doc(alive.id))
        try store.save(doc(orphan))

        XCTAssertEqual(try store.deleteOrphans(), 1)
        XCTAssertEqual(try store.taskIDsWithDocument(), [alive.id])
        XCTAssertEqual(try store.deleteOrphans(), 0)
    }

    /// Achado do review: tarefa com payload ilegível some da lista do `SwiftDataTaskStore`, mas a
    /// linha fica — o documento dela não é órfão e não pode ser apagado.
    func test_deleteOrphans_preservaDocumentoDeTarefaIlegivel() throws {
        let store = SwiftDataTaskDocumentStore(database: database)
        let unreadable = UUID()
        database.context.insert(TaskRecord(id: unreadable, position: 0, createdAt: Date(), completedAt: nil,
                                           dueDate: nil, parentID: nil, payload: Data("{lixo".utf8)))
        try database.context.save()
        try store.save(doc(unreadable))
        XCTAssertEqual(try SwiftDataTaskStore(database: database).loadTasks(), [])

        XCTAssertEqual(try store.deleteOrphans(), 0)
        XCTAssertEqual(try store.taskIDsWithDocument(), [unreadable])
    }

    // MARK: - Migração V1 → V2

    /// Banco gravado pela 1.17/1.18 (esquema V1, sem tabela de documentos) abre na V2 sem perder
    /// nada e sem cair no `.bak` — o primeiro estágio real do `TomafocoMigrationPlan`.
    func test_bancoV1_abreNaV2_semPerderDados() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tomafoco-v1-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("Tomafoco.store")

        let task = FocusTask(id: UUID(), title: "Antiga", source: .manual,
                             createdAt: Date(timeIntervalSince1970: 1_800_000_000), tags: ["x"])
        let project = Project(id: UUID(), title: "P", createdAt: Date(timeIntervalSince1970: 1))
        do {
            // Exatamente como a V1 abria o banco: esquema V1 + plano só com a V1.
            let container = try ModelContainer(for: Schema(versionedSchema: TomafocoSchemaV1.self),
                                               migrationPlan: V1OnlyPlan.self,
                                               configurations: [ModelConfiguration(url: url)])
            let context = ModelContext(container)
            context.insert(TaskRecord(id: task.id, position: 0, createdAt: task.createdAt, completedAt: nil,
                                      dueDate: nil, parentID: nil, payload: try PayloadCoding.encoder.encode(task)))
            context.insert(ProjectRecord(id: project.id, title: project.title,
                                         payload: try PayloadCoding.encoder.encode(project)))
            context.insert(TagRecord(name: "x", position: 0))
            try context.save()
        }

        let migrated = try TomafocoDatabase.open(at: url, retryDelay: 0)
        XCTAssertFalse(migrated.wasReset)
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertFalse(names.contains { $0.contains(".bak-") }, "\(names)")
        XCTAssertEqual(try SwiftDataTaskStore(database: migrated).loadTasks(), [task])
        XCTAssertEqual(try SwiftDataProjectStore(database: migrated).loadProjects(), [project])

        let documents = SwiftDataTaskDocumentStore(database: migrated)
        try documents.save(doc(task.id))
        XCTAssertEqual(try documents.document(taskID: task.id)?.markdown, doc(task.id).markdown)
    }

    private enum V1OnlyPlan: SchemaMigrationPlan {
        static var schemas: [any VersionedSchema.Type] { [TomafocoSchemaV1.self] }
        static var stages: [MigrationStage] { [] }
    }
}
