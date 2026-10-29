import XCTest
import TomafocoDomain
import TomafocoTestSupport
@testable import TomafocoApplication

/// Tarefa diária (FEAT-004): concluir fecha a tarefa como qualquer outra e cria um clone com
/// vencimento amanhã. A concluída não é reaberta.
@MainActor
final class ManageTasksDailyTests: XCTestCase {

    private var repo: InMemoryTaskRepository!
    private var importer: StubTaskImporter!
    private var calendar: Calendar!
    private var now: Date!
    private var sut: ManageTasksUseCase!

    override func setUp() {
        super.setUp()
        repo = InMemoryTaskRepository()
        importer = StubTaskImporter()
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Sao_Paulo")!
        now = date(27, 9)
        sut = ManageTasksUseCase(
            tasks: repo, importer: importer, now: { self.now },
            shouldSyncReminderCompletion: { true }, calendar: calendar)
    }

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    private func addDaily(_ title: String = "Inglês") throws -> FocusTask {
        let task = try sut.addTask(title: title)
        try sut.setRepeatsDaily(id: task.id, true)
        return task
    }

    private func stored(_ id: UUID) -> FocusTask { repo.tasks.first { $0.id == id }! }

    private func clone(of id: UUID) -> FocusTask? {
        let clones = repo.tasks.filter { $0.id != id && $0.title == stored(id).title }
        XCTAssertLessThanOrEqual(clones.count, 1, "mais de um clone")
        return clones.first
    }

    func test_completeTask_diaria_fechaECriaCloneComVencimentoAmanha() async throws {
        let task = try addDaily()
        try sut.editTask(id: task.id, title: "Inglês", tags: ["estudo"], dueDate: date(27, 18, 30),
                         priority: .high, repeatsDaily: true)
        let savesBefore = repo.saveCallCount

        try await sut.completeTask(id: task.id)

        XCTAssertEqual(stored(task.id).completedAt, now)
        let clone = try XCTUnwrap(clone(of: task.id))
        XCTAssertNil(clone.completedAt)
        XCTAssertEqual(clone.createdAt, now)
        XCTAssertEqual(clone.dueDate, date(28, 18, 30))
        XCTAssertEqual(clone.tags, ["estudo"])
        XCTAssertEqual(clone.priority, TaskPriority.high.rawPriority)
        XCTAssertTrue(clone.repeatsDaily)
        XCTAssertEqual(try sut.activeTasks().map(\.id), [clone.id])
        XCTAssertEqual(repo.saveCallCount, savesBefore + 1, "o clone entra na mesma gravação da conclusão")
    }

    func test_completeTask_diaria_naoMexeNoLogNemNoHistorico() async throws {
        let task = try addDaily()
        try sut.addHistoryEntry(taskID: task.id, text: "anotação")

        try await sut.completeTask(id: task.id)

        XCTAssertEqual(stored(task.id).completionLog, [])
        XCTAssertEqual(stored(task.id).history.map(\.text), ["anotação"])
        let clone = try XCTUnwrap(clone(of: task.id))
        XCTAssertEqual(clone.history, [])
        XCTAssertEqual(clone.completionLog, [])
    }

    func test_completeTask_diariaSemVencimento_cloneVenceAmanhaFimDoDia() async throws {
        let task = try addDaily()
        try await sut.completeTask(id: task.id)
        XCTAssertEqual(try XCTUnwrap(clone(of: task.id)).dueDate, date(28, 23, 59))
    }

    func test_completeTask_cloneTambemEDiario_concluirDeNovoGeraOutroClone() async throws {
        let task = try addDaily()
        try await sut.completeTask(id: task.id)
        let first = try XCTUnwrap(clone(of: task.id))

        now = date(28, 10)
        try await sut.completeTask(id: first.id)

        XCTAssertEqual(stored(first.id).completedAt, date(28, 10))
        XCTAssertEqual(repo.tasks.count, 3)
        XCTAssertEqual(try sut.activeTasks().count, 1)
        XCTAssertEqual(try sut.activeTasks()[0].dueDate, date(29, 23, 59))
    }

    func test_completeTask_naoDiaria_concluiNormalSemClone() async throws {
        let task = try sut.addTask(title: "Boleto")
        try await sut.completeTask(id: task.id)
        XCTAssertEqual(stored(task.id).completedAt, now)
        XCTAssertEqual(repo.tasks.count, 1)
    }

    /// A diária fecha de verdade, então o lembrete fecha junto; o clone leva o `reminderID`
    /// (lembrete recorrente avança sozinho no Lembretes e segue "importado" no picker).
    func test_completeTask_diariaDoLembretes_espelhaEMantemVinculoNoClone() async throws {
        _ = await sut.importReminder(ImportedReminder(reminderID: "r1", title: "Remédio",
                                                      listName: "Casa", isCompleted: false))
        let id = repo.tasks[0].id
        try sut.setRepeatsDaily(id: id, true)

        let outcome = try await sut.completeTask(id: id)

        XCTAssertEqual(outcome, .synced)
        XCTAssertEqual(importer.completionWriteBacks.count, 1)
        let clone = try XCTUnwrap(clone(of: id))
        XCTAssertEqual(clone.source, .reminders)
        XCTAssertEqual(clone.reminderID, "r1")
    }

    func test_completeTask_subtarefaDiaria_cloneFicaNoMesmoPai() async throws {
        let parent = try sut.addTask(title: "Treino")
        let child = try sut.addSubtask(parentID: parent.id, title: "alongar")
        try sut.setRepeatsDaily(id: child.id, true)

        try await sut.completeTask(id: child.id)

        XCTAssertEqual(stored(child.id).completedAt, now)
        XCTAssertNil(stored(parent.id).completedAt)
        let clone = try XCTUnwrap(clone(of: child.id))
        XCTAssertEqual(clone.parentID, parent.id)
    }

    func test_reopenTask_diariaConcluida_naoRemoveOClone() async throws {
        let task = try addDaily()
        try await sut.completeTask(id: task.id)

        try await sut.reopenTask(id: task.id)

        XCTAssertNil(stored(task.id).completedAt)
        XCTAssertEqual(repo.tasks.count, 2)
    }

    func test_editTask_desligarRepeticaoNaoApagaNada() async throws {
        let task = try addDaily()
        try sut.addHistoryEntry(taskID: task.id, text: "anotação")

        try sut.editTask(id: task.id, title: "Inglês", tags: [], dueDate: nil, priority: .none, repeatsDaily: false)

        XCTAssertFalse(stored(task.id).repeatsDaily)
        XCTAssertEqual(stored(task.id).history.count, 1)
    }
}
