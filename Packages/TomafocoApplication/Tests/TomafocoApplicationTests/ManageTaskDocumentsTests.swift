import XCTest
import TomafocoDomain
import TomafocoTestSupport
@testable import TomafocoApplication

/// Documento em markdown das tarefas (FEAT-007): autosave, apagar em cascata com a tarefa e
/// cópia para o clone da diária (lista e Kanban), tudo na mesma transação das tarefas.
@MainActor
final class ManageTaskDocumentsTests: XCTestCase {

    private var taskRepo: InMemoryTaskRepository!
    private var documentRepo: InMemoryTaskDocumentRepository!
    private var unitOfWork: InMemoryUnitOfWork!
    private var calendar: Calendar!
    private var now: Date!
    private var tasks: ManageTasksUseCase!
    private var sut: ManageTaskDocumentsUseCase!

    /// Desmarca pelo texto — o parser real é testado no pacote TomafocoMarkdown.
    private struct StubResetter: ChecklistResetting {
        func uncheckingAll(_ markdown: String) -> String {
            markdown.replacingOccurrences(of: "[x]", with: "[ ]")
        }
    }

    private struct Boom: Error {}

    override func setUp() {
        super.setUp()
        taskRepo = InMemoryTaskRepository()
        documentRepo = InMemoryTaskDocumentRepository()
        unitOfWork = InMemoryUnitOfWork(tasks: taskRepo, documents: documentRepo)
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Sao_Paulo")!
        now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 25, hour: 9))!
        tasks = ManageTasksUseCase(
            tasks: taskRepo, importer: StubTaskImporter(), now: { self.now }, calendar: calendar,
            documents: documentRepo, unitOfWork: unitOfWork, checklistResetter: StubResetter())
        sut = ManageTaskDocumentsUseCase(documents: documentRepo, tasks: taskRepo, now: { self.now })
    }

    private func later(_ minutes: Int) { now = now.addingTimeInterval(TimeInterval(minutes * 60)) }

    // MARK: - save

    func test_save_criaEDepoisAtualiza() throws {
        let task = try tasks.addTask(title: "T")

        let created = try sut.save(taskID: task.id, markdown: "# Plano")
        XCTAssertEqual(created, .saved(TaskDocument(taskID: task.id, markdown: "# Plano", updatedAt: now), created: true))
        XCTAssertTrue(created.changesPresence)

        later(5)
        let updated = try sut.save(taskID: task.id, markdown: "# Plano 2")
        XCTAssertEqual(updated, .saved(TaskDocument(taskID: task.id, markdown: "# Plano 2", updatedAt: now), created: false))
        XCTAssertFalse(updated.changesPresence)
        XCTAssertEqual(try sut.document(taskID: task.id)?.markdown, "# Plano 2")
    }

    func test_save_textoIgual_naoRegravaNemMudaData() throws {
        let task = try tasks.addTask(title: "T")
        try sut.save(taskID: task.id, markdown: "a")
        let firstSave = try sut.document(taskID: task.id)?.updatedAt
        later(5)

        XCTAssertEqual(try sut.save(taskID: task.id, markdown: "a"), .unchanged)
        XCTAssertEqual(try sut.document(taskID: task.id)?.updatedAt, firstSave)
    }

    func test_save_emBranco_apagaOuNaoFazNada() throws {
        let task = try tasks.addTask(title: "T")
        XCTAssertEqual(try sut.save(taskID: task.id, markdown: "  \n"), .unchanged)

        try sut.save(taskID: task.id, markdown: "a")
        let deleted = try sut.save(taskID: task.id, markdown: "\n\n")
        XCTAssertEqual(deleted, .deleted)
        XCTAssertTrue(deleted.changesPresence)
        XCTAssertEqual(try sut.taskIDsWithDocument(), [])
    }

    func test_save_acimaDoLimite_lancaENaoGrava() throws {
        let task = try tasks.addTask(title: "T")
        let big = String(repeating: "a", count: TaskDocument.maxByteCount + 1)
        XCTAssertThrowsError(try sut.save(taskID: task.id, markdown: big)) { error in
            XCTAssertEqual(error as? DomainError, .documentTooLarge(maxBytes: TaskDocument.maxByteCount))
        }
        XCTAssertNil(try sut.document(taskID: task.id))
    }

    func test_save_tarefaApagada_naoGrava() throws {
        XCTAssertEqual(try sut.save(taskID: UUID(), markdown: "a"), .taskNotFound)
        XCTAssertEqual(try sut.taskIDsWithDocument(), [])
    }

    // MARK: - Apagar tarefa

    func test_deleteTask_apagaDocumentoDaTarefaEDasFilhas_numaTransacao() throws {
        let parent = try tasks.addTask(title: "Pai")
        let child = try tasks.addSubtask(parentID: parent.id, title: "Filha")
        let other = try tasks.addTask(title: "Outra")
        for task in [parent, child, other] { try sut.save(taskID: task.id, markdown: "doc") }
        let performsBefore = unitOfWork.performCount

        try tasks.deleteTask(id: parent.id)

        XCTAssertEqual(try sut.taskIDsWithDocument(), [other.id])
        XCTAssertEqual(unitOfWork.performCount, performsBefore + 1)
    }

    func test_deleteTask_falhaNoDocumento_desfazTudo() throws {
        let task = try tasks.addTask(title: "T")
        try sut.save(taskID: task.id, markdown: "doc")
        documentRepo.saveError = Boom()

        XCTAssertThrowsError(try tasks.deleteTask(id: task.id))

        XCTAssertEqual(taskRepo.tasks.map(\.id), [task.id], "tarefa volta junto")
        XCTAssertNotNil(documentRepo.documents[task.id])
    }

    // MARK: - Diária

    private func addDaily() throws -> FocusTask {
        let task = try tasks.addTask(title: "Rotina")
        try tasks.setRepeatsDaily(id: task.id, true)
        return task
    }

    private func clone(of task: FocusTask) throws -> FocusTask {
        try XCTUnwrap(taskRepo.tasks.first { $0.id != task.id && $0.title == task.title })
    }

    func test_completeTask_diaria_cloneLevaDocumentoComChecklistDesmarcado() async throws {
        let task = try addDaily()
        try sut.save(taskID: task.id, markdown: "- [x] café\n- [ ] água")
        later(60)

        try await tasks.completeTask(id: task.id)

        let clone = try clone(of: task)
        XCTAssertEqual(try sut.document(taskID: clone.id),
                       TaskDocument(taskID: clone.id, markdown: "- [ ] café\n- [ ] água", updatedAt: now))
        XCTAssertEqual(try sut.document(taskID: task.id)?.markdown, "- [x] café\n- [ ] água",
                       "a concluída guarda o documento como estava")
    }

    func test_completeTask_diariaSemDocumento_cloneSemDocumento() async throws {
        let task = try addDaily()
        try await tasks.completeTask(id: task.id)
        XCTAssertEqual(try sut.taskIDsWithDocument(), [])
        _ = try clone(of: task)
    }

    func test_completeTask_naoDiaria_naoCopiaNada() async throws {
        let task = try tasks.addTask(title: "Normal")
        try sut.save(taskID: task.id, markdown: "doc")
        try await tasks.completeTask(id: task.id)
        XCTAssertEqual(try sut.taskIDsWithDocument(), [task.id])
    }

    func test_completeTask_diaria_falhaAoCopiar_desfazConclusaoEClone() async throws {
        let task = try addDaily()
        try sut.save(taskID: task.id, markdown: "doc")
        documentRepo.saveError = Boom()

        do {
            try await tasks.completeTask(id: task.id)
            XCTFail("esperava erro")
        } catch {}

        XCTAssertEqual(taskRepo.tasks.map(\.id), [task.id], "clone não pode ficar sem o documento")
        XCTAssertNil(taskRepo.tasks[0].completedAt)
    }

    func test_filhaDiariaFechadaPelaCascataDoPai_naoGeraDocumento() async throws {
        let parent = try tasks.addTask(title: "Pai")
        let child = try tasks.addSubtask(parentID: parent.id, title: "Filha")
        try tasks.setRepeatsDaily(id: child.id, true)
        try sut.save(taskID: child.id, markdown: "- [x] a")

        try await tasks.completeTask(id: parent.id)

        XCTAssertEqual(taskRepo.tasks.count, 2, "sem clone")
        XCTAssertEqual(try sut.taskIDsWithDocument(), [child.id])
    }

    func test_kanban_diariaParaDone_cloneLevaDocumento() async throws {
        let kanban = ManageKanbanUseCase(boards: InMemoryKanbanBoardRepository(), tasks: tasks, now: { self.now })
        let task = try addDaily()
        try sut.save(taskID: task.id, markdown: "- [x] a")

        try await kanban.moveTask(id: task.id, toLane: try kanban.board().doneLane.id)

        let clone = try clone(of: task)
        XCTAssertEqual(try sut.document(taskID: clone.id)?.markdown, "- [ ] a")
    }
}
