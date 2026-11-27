import XCTest
import TomafocoDomain
import TomafocoTestSupport
@testable import TomafocoApplication

/// Duplicar tarefa (RF-09.19): cópia aberta e manual ao lado da original, título "(cópia)" único
/// entre irmãos, subtarefas e documento juntos, numa transação.
@MainActor
final class ManageTasksDuplicateTests: XCTestCase {

    private var taskRepo: InMemoryTaskRepository!
    private var documentRepo: InMemoryTaskDocumentRepository!
    private var unitOfWork: InMemoryUnitOfWork!
    private var now: Date!
    private var sut: ManageTasksUseCase!

    private struct Boom: Error {}

    override func setUp() {
        super.setUp()
        taskRepo = InMemoryTaskRepository()
        documentRepo = InMemoryTaskDocumentRepository()
        unitOfWork = InMemoryUnitOfWork(tasks: taskRepo, documents: documentRepo)
        now = Date(timeIntervalSince1970: 1_900_000_000)
        sut = ManageTasksUseCase(
            tasks: taskRepo, importer: StubTaskImporter(), now: { self.now },
            documents: documentRepo, unitOfWork: unitOfWork)
    }

    private func stored(_ id: UUID) -> FocusTask? { taskRepo.tasks.first { $0.id == id } }

    func test_duplicate_copiaCamposEZeraHistoricoConclusaoEOrigem() async throws {
        let lane = UUID()
        let original = FocusTask(
            id: UUID(), title: "Boleto", source: .reminders, reminderID: "r1",
            createdAt: Date(timeIntervalSince1970: 0), completedAt: Date(timeIntervalSince1970: 10),
            tags: ["casa"], notes: "nota", dueDate: Date(timeIntervalSince1970: 500), priority: 1,
            sourceURL: "https://x.com",
            history: [TaskHistoryEntry(id: UUID(), createdAt: Date(timeIntervalSince1970: 5), text: "h")],
            repeatsDaily: true, laneIDs: [lane], isUrgent: true, projectID: UUID())
        taskRepo.tasks = [original]
        later()

        let copy = try XCTUnwrap(try sut.duplicateTask(id: original.id))

        XCTAssertNotEqual(copy.id, original.id)
        XCTAssertEqual(copy.title, "Boleto (cópia)")
        XCTAssertEqual(copy.source, .manual)
        XCTAssertNil(copy.reminderID)
        XCTAssertEqual(copy.createdAt, now)
        XCTAssertNil(copy.completedAt)
        XCTAssertEqual(copy.history, [])
        XCTAssertEqual(copy.tags, ["casa"])
        XCTAssertEqual(copy.notes, "nota")
        XCTAssertEqual(copy.dueDate, original.dueDate)
        XCTAssertEqual(copy.priority, 1)
        XCTAssertEqual(copy.sourceURL, "https://x.com")
        XCTAssertTrue(copy.repeatsDaily)
        XCTAssertEqual(copy.laneIDs, [lane], "aparece ao lado da original no quadro")
        XCTAssertTrue(copy.isUrgent)
        XCTAssertEqual(copy.projectID, original.projectID)
        XCTAssertEqual(stored(original.id), original, "original intacta")
        XCTAssertEqual(taskRepo.tasks.count, 2)
    }

    func test_duplicate_tituloUnicoEntreIrmaos_semEmpilharSufixo() throws {
        let a = try sut.addTask(title: "Deploy")
        let c1 = try XCTUnwrap(try sut.duplicateTask(id: a.id))
        let c2 = try XCTUnwrap(try sut.duplicateTask(id: a.id))
        let c3 = try XCTUnwrap(try sut.duplicateTask(id: c1.id))
        XCTAssertEqual([c1.title, c2.title, c3.title], ["Deploy (cópia)", "Deploy (cópia 2)", "Deploy (cópia 3)"])
    }

    func test_duplicateTitle_casosPuros() {
        XCTAssertEqual(FocusTask.duplicateTitle(for: "X") { _ in false }, "X (cópia)")
        XCTAssertEqual(FocusTask.duplicateTitle(for: "X (cópia 7)") { _ in false }, "X (cópia)")
        XCTAssertEqual(FocusTask.duplicateTitle(for: "X") { $0 == "X (cópia)" }, "X (cópia 2)")
        XCTAssertEqual(FocusTask.duplicateTitle(for: "Plano (cópias)") { _ in false }, "Plano (cópias) (cópia)")
    }

    /// Tarefa pai: as filhas vêm junto, abertas, com os mesmos títulos, sob a cópia.
    func test_duplicate_pai_levaFilhasAbertas() async throws {
        let parent = try sut.addTask(title: "Apresentação")
        let a = try sut.addSubtask(parentID: parent.id, title: "Esboço")
        let b = try sut.addSubtask(parentID: parent.id, title: "Revisão")
        try await sut.completeTask(id: b.id)

        let copy = try XCTUnwrap(try sut.duplicateTask(id: parent.id))

        let children = taskRepo.tasks.filter { $0.parentID == copy.id }
        XCTAssertEqual(Set(children.map(\.title)), ["Esboço", "Revisão"])
        XCTAssertTrue(children.allSatisfy { !$0.isCompleted })
        XCTAssertEqual(taskRepo.tasks.filter { $0.parentID == parent.id }.map(\.id).sorted { $0.uuidString < $1.uuidString },
                       [a.id, b.id].sorted { $0.uuidString < $1.uuidString }, "filhas da original não mudam")
    }

    /// Subtarefa: cópia sob o mesmo pai; pai concluído reabre (subtarefa ativa ⇒ pai ativo).
    func test_duplicate_subtarefa_mesmoPai_reabrePaiConcluido() async throws {
        let parent = try sut.addTask(title: "Apresentação")
        let child = try sut.addSubtask(parentID: parent.id, title: "Esboço")
        try await sut.completeTask(id: parent.id)

        let copy = try XCTUnwrap(try sut.duplicateTask(id: child.id))

        XCTAssertEqual(copy.parentID, parent.id)
        XCTAssertEqual(copy.title, "Esboço (cópia)")
        XCTAssertNil(stored(parent.id)?.completedAt)
    }

    func test_duplicate_copiaDocumentos_daTarefaEDasFilhas() throws {
        let parent = try sut.addTask(title: "P")
        let child = try sut.addSubtask(parentID: parent.id, title: "F")
        try documentRepo.save(TaskDocument(taskID: parent.id, markdown: "- [x] feito", updatedAt: now))
        try documentRepo.save(TaskDocument(taskID: child.id, markdown: "# filha", updatedAt: now))

        let copy = try XCTUnwrap(try sut.duplicateTask(id: parent.id))
        let childCopy = try XCTUnwrap(taskRepo.tasks.first { $0.parentID == copy.id })

        XCTAssertEqual(try documentRepo.document(taskID: copy.id)?.markdown, "- [x] feito", "copiado como está")
        XCTAssertEqual(try documentRepo.document(taskID: childCopy.id)?.markdown, "# filha")
        XCTAssertEqual(try documentRepo.document(taskID: parent.id)?.markdown, "- [x] feito")
    }

    func test_duplicate_falhaAoGravarDocumento_desfazTudo() throws {
        let task = try sut.addTask(title: "P")
        try documentRepo.save(TaskDocument(taskID: task.id, markdown: "doc", updatedAt: now))
        documentRepo.saveError = Boom()

        XCTAssertThrowsError(try sut.duplicateTask(id: task.id))

        XCTAssertEqual(taskRepo.tasks.map(\.id), [task.id], "cópia não ficou sem o documento")
    }

    func test_duplicate_inexistente_nil() throws {
        XCTAssertNil(try sut.duplicateTask(id: UUID()))
        XCTAssertEqual(taskRepo.saveCallCount, 0)
    }

    private func later() { now = now.addingTimeInterval(3600) }
}
