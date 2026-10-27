import XCTest
import TomafocoDomain
import TomafocoTestSupport
@testable import TomafocoApplication

/// Tarefa diária (FEAT-004): concluir mantém a tarefa ativa, registra a conclusão no log e no
/// histórico e empurra o vencimento para amanhã.
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

    func test_completeTask_diaria_continuaAtivaComVencimentoAmanha() async throws {
        let task = try addDaily()
        try sut.editTask(id: task.id, title: "Inglês", tags: [], dueDate: date(27, 18, 30),
                         priority: .none, repeatsDaily: true)

        try await sut.completeTask(id: task.id)

        XCTAssertNil(repo.tasks[0].completedAt)
        XCTAssertEqual(repo.tasks[0].dueDate, date(28, 18, 30))
        XCTAssertEqual(try sut.activeTasks().map(\.id), [task.id])
    }

    func test_completeTask_diaria_registraConclusaoNoLogENoHistorico() async throws {
        let task = try addDaily()
        try await sut.completeTask(id: task.id)

        XCTAssertEqual(repo.tasks[0].completionLog, [now])
        XCTAssertEqual(repo.tasks[0].history.count, 1)
        XCTAssertEqual(repo.tasks[0].history[0].createdAt, now)
        XCTAssertEqual(repo.tasks[0].history[0].text, "Concluída em 27/10/2026")
    }

    func test_completeTask_diariaSemVencimento_venceAmanhaFimDoDia() async throws {
        let task = try addDaily()
        try await sut.completeTask(id: task.id)
        XCTAssertEqual(repo.tasks[0].dueDate, date(28, 23, 59))
    }

    func test_completeTask_naoDiaria_concluiNormalSemLogNemHistorico() async throws {
        let task = try sut.addTask(title: "Boleto")
        try await sut.completeTask(id: task.id)
        XCTAssertEqual(repo.tasks[0].completedAt, now)
        XCTAssertEqual(repo.tasks[0].completionLog, [])
        XCTAssertEqual(repo.tasks[0].history, [])
    }

    func test_completeTask_diariaDoLembretes_naoMarcaConcluidoLa() async throws {
        _ = await sut.importReminder(ImportedReminder(reminderID: "r1", title: "Remédio",
                                                      listName: "Casa", isCompleted: false))
        let id = repo.tasks[0].id
        try sut.setRepeatsDaily(id: id, true)

        let outcome = try await sut.completeTask(id: id)

        XCTAssertEqual(outcome, .notApplicable)
        XCTAssertTrue(importer.completionWriteBacks.isEmpty)
    }

    func test_editTask_persisteRepeticaoSemPerderHistoricoNemLog() async throws {
        let task = try addDaily()
        try await sut.completeTask(id: task.id)

        try sut.editTask(id: task.id, title: "Inglês", tags: [], dueDate: nil, priority: .none, repeatsDaily: false)
        XCTAssertFalse(repo.tasks[0].repeatsDaily)
        XCTAssertEqual(repo.tasks[0].history.count, 1)
        XCTAssertEqual(repo.tasks[0].completionLog, [now])
    }
}
