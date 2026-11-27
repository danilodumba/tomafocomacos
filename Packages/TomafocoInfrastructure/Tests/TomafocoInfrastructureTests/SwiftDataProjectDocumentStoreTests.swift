import XCTest
import SwiftData
import TomafocoDomain
@testable import TomafocoInfrastructure

/// Documentos dos projetos (FEAT-009) + migração do banco V2 → V3.
@MainActor
final class SwiftDataProjectDocumentStoreTests: XCTestCase {

    private var database: TomafocoDatabase!
    private var store: SwiftDataProjectDocumentStore!
    private let date = Date(timeIntervalSince1970: 1_900_000_000)

    override func setUp() async throws {
        database = try TomafocoDatabase.inMemory()
        store = SwiftDataProjectDocumentStore(database: database)
    }

    private func doc(_ projectID: UUID, _ title: String, _ markdown: String = "") -> ProjectDocument {
        ProjectDocument(id: UUID(), projectID: projectID, title: title, markdown: markdown, createdAt: date, updatedAt: date)
    }

    private func addProject() throws -> UUID {
        let project = Project(id: UUID(), title: "P \(UUID())", createdAt: date)
        try SwiftDataProjectStore(database: database).upsert(project)
        return project.id
    }

    func test_salvaLe_substitui_eListaResumosDoProjeto() throws {
        let projectID = UUID(), other = UUID()
        var a = doc(projectID, "A", "# a")
        try store.save(a)
        try store.save(doc(projectID, "B"))
        try store.save(doc(other, "C"))

        XCTAssertEqual(try store.document(id: a.id), a)
        XCTAssertEqual(Set(try store.summaries(projectID: projectID).map(\.title)), ["A", "B"])

        a.title = "A2"
        a.markdown = "novo"
        try store.save(a)
        XCTAssertEqual(try store.document(id: a.id), a)
        XCTAssertEqual(try store.summaries(projectID: projectID).first { $0.id == a.id }?.title, "A2")
        XCTAssertFalse(database.context.hasChanges, "grava na hora")
    }

    func test_delete_eDeleteDoProjeto() throws {
        let projectID = UUID(), other = UUID()
        let a = doc(projectID, "A"), b = doc(projectID, "B"), c = doc(other, "C")
        for d in [a, b, c] { try store.save(d) }
        try store.delete(id: a.id)
        XCTAssertNil(try store.document(id: a.id))
        try store.delete(projectID: projectID)
        XCTAssertEqual(try store.summaries(projectID: projectID), [])
        XCTAssertNotNil(try store.document(id: c.id))
    }

    func test_projetoENDocumentosNaMesmaTransacao_rollback() throws {
        let projectID = try addProject()
        struct Boom: Error {}
        XCTAssertThrowsError(try database.perform {
            try store.save(doc(projectID, "A"))
            throw Boom()
        })
        XCTAssertEqual(try store.summaries(projectID: projectID), [])
    }

    func test_deleteOrphans_soDeProjetoSemLinha() throws {
        let existing = try addProject()
        let kept = doc(existing, "fica"), orphan = doc(UUID(), "órfão")
        try store.save(kept)
        try store.save(orphan)
        XCTAssertEqual(try store.deleteOrphans(), 1)
        XCTAssertNotNil(try store.document(id: kept.id))
        XCTAssertNil(try store.document(id: orphan.id))
        XCTAssertEqual(try store.deleteOrphans(), 0)
    }

    // MARK: - Migração V2 → V3

    /// Banco gravado pela 1.19 (esquema V2: com documentos das tarefas, sem os dos projetos) abre
    /// na V3 sem perder nada e sem cair no `.bak`.
    func test_bancoV2_abreNaV3_semPerderDados() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tomafoco-v2-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("Tomafoco.store")

        let task = FocusTask(id: UUID(), title: "Antiga", source: .manual, createdAt: date, tags: ["x"])
        let project = Project(id: UUID(), title: "P", createdAt: date)
        let taskDoc = TaskDocument(taskID: task.id, markdown: "# doc", updatedAt: date)
        do {
            // Exatamente como a 1.19 abria o banco: esquema V2 + plano até a V2.
            let container = try ModelContainer(for: Schema(versionedSchema: TomafocoSchemaV2.self),
                                               migrationPlan: UpToV2Plan.self,
                                               configurations: [ModelConfiguration(url: url)])
            let context = ModelContext(container)
            context.insert(TaskRecord(id: task.id, position: 0, createdAt: task.createdAt, completedAt: nil,
                                      dueDate: nil, parentID: nil, payload: try PayloadCoding.encoder.encode(task)))
            context.insert(ProjectRecord(id: project.id, title: project.title,
                                         payload: try PayloadCoding.encoder.encode(project)))
            context.insert(TaskDocumentRecord(taskID: task.id, updatedAt: date,
                                              payload: try PayloadCoding.encoder.encode(taskDoc)))
            try context.save()
        }

        let migrated = try TomafocoDatabase.open(at: url, retryDelay: 0)
        XCTAssertFalse(migrated.wasReset)
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertFalse(names.contains { $0.contains(".bak-") }, "\(names)")
        XCTAssertEqual(try SwiftDataTaskStore(database: migrated).loadTasks(), [task])
        XCTAssertEqual(try SwiftDataProjectStore(database: migrated).loadProjects(), [project])
        XCTAssertEqual(try SwiftDataTaskDocumentStore(database: migrated).document(taskID: task.id), taskDoc)

        let documents = SwiftDataProjectDocumentStore(database: migrated)
        let projectDoc = doc(project.id, "Spec", "# spec")
        try documents.save(projectDoc)
        XCTAssertEqual(try documents.document(id: projectDoc.id), projectDoc)
    }

    private enum UpToV2Plan: SchemaMigrationPlan {
        static var schemas: [any VersionedSchema.Type] { [TomafocoSchemaV1.self, TomafocoSchemaV2.self] }
        static var stages: [MigrationStage] { [TomafocoMigrationPlan.migrateV1toV2] }
    }
}
