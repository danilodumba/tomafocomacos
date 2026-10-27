import XCTest
import TomafocoDomain
import TomafocoTestSupport
@testable import TomafocoApplication

/// Quadro Kanban (FEAT-005): movimentação (com conclusão/reabertura e histórico), raias e
/// configuração do quadro.
final class ManageKanbanUseCaseTests: XCTestCase {

    private var taskRepo: InMemoryTaskRepository!
    private var boardRepo: InMemoryKanbanBoardRepository!
    private var importer: StubTaskImporter!
    private var calendar: Calendar!
    private var now: Date!
    private var tasks: ManageTasksUseCase!
    private var sut: ManageKanbanUseCase!

    override func setUp() {
        super.setUp()
        taskRepo = InMemoryTaskRepository()
        boardRepo = InMemoryKanbanBoardRepository()
        importer = StubTaskImporter()
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Sao_Paulo")!
        now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 27, hour: 9))!
        tasks = ManageTasksUseCase(
            tasks: taskRepo, importer: importer, now: { self.now },
            shouldSyncReminderCompletion: { true }, calendar: calendar, kanbanBoards: boardRepo)
        sut = ManageKanbanUseCase(boards: boardRepo, tasks: tasks, now: { self.now })
    }

    private func lanes() throws -> (todo: KanbanLane, doing: KanbanLane, done: KanbanLane) {
        let board = try sut.board()
        return (board.lanes[0], board.lanes[1], board.doneLane)
    }

    private func stored(_ id: UUID) -> FocusTask { taskRepo.tasks.first { $0.id == id }! }

    // MARK: - Quadro padrão

    func test_board_criaPadraoUmaVez() throws {
        let first = try sut.board()
        let second = try sut.board()
        XCTAssertEqual(first, second)
        XCTAssertEqual(boardRepo.saveCount, 1)
        XCTAssertEqual(first.lanes.map(\.title), ["A fazer", "Em andamento", "Concluído"])
    }

    // MARK: - Movimentação

    func test_moveTask_entreAbertas_gravaRaiaEHistorico() async throws {
        let (_, doing, _) = try lanes()
        let task = try tasks.addTask(title: "Deploy")

        let outcome = try await sut.moveTask(id: task.id, toLane: doing.id)

        XCTAssertEqual(outcome, .notApplicable)
        XCTAssertEqual(stored(task.id).laneID, doing.id)
        XCTAssertEqual(stored(task.id).history.map(\.text), ["Movida: A fazer → Em andamento"])
        XCTAssertEqual(stored(task.id).history.first?.createdAt, now)
    }

    func test_moveTask_mesmaRaia_noOp() async throws {
        let (todo, _, _) = try lanes()
        let task = try tasks.addTask(title: "Deploy")
        try await sut.moveTask(id: task.id, toLane: todo.id)
        XCTAssertEqual(stored(task.id).history, [])
        XCTAssertNil(stored(task.id).laneID)
    }

    func test_moveTask_tarefaOuRaiaInexistente_noOp() async throws {
        let (_, doing, _) = try lanes()
        let task = try tasks.addTask(title: "Deploy")
        let unknownTask = try await sut.moveTask(id: UUID(), toLane: doing.id)
        let unknownLane = try await sut.moveTask(id: task.id, toLane: UUID())
        XCTAssertEqual(unknownTask, .notApplicable)
        XCTAssertEqual(unknownLane, .notApplicable)
        XCTAssertEqual(stored(task.id).history, [])
    }

    func test_moveTask_paraDone_concluiEspelhaEMantemRaiaAnterior() async throws {
        let (_, doing, done) = try lanes()
        _ = await tasks.importReminder(ImportedReminder(reminderID: "r1", title: "Boleto", listName: "Casa", isCompleted: false))
        let task = taskRepo.tasks[0]
        try await sut.moveTask(id: task.id, toLane: doing.id)

        let outcome = try await sut.moveTask(id: task.id, toLane: done.id)

        XCTAssertEqual(outcome, .synced)
        XCTAssertEqual(stored(task.id).completedAt, now)
        XCTAssertEqual(stored(task.id).laneID, doing.id)
        XCTAssertEqual(stored(task.id).history.last?.text, "Movida: Em andamento → Concluído")
        XCTAssertEqual(importer.completionWriteBacks.last?.completed, true)
    }

    /// FEAT-003: arrastar o pai para Done conclui em cascata — a filha fecha e, como a raia é
    /// derivada da conclusão, o cartão dela vai para a Done também, numa gravação só.
    func test_moveTask_paraDone_cascataLevaFilhasParaDone() async throws {
        let (_, doing, done) = try lanes()
        let task = try tasks.addTask(title: "Apresentação")
        let child = try tasks.addSubtask(parentID: task.id, title: "Esboço")
        try await sut.moveTask(id: child.id, toLane: doing.id)
        let saves = taskRepo.saveCallCount

        try await sut.moveTask(id: task.id, toLane: done.id)

        XCTAssertEqual(stored(child.id).completedAt, now)
        XCTAssertEqual(try sut.board().lane(for: stored(child.id)).id, done.id)
        XCTAssertEqual(taskRepo.saveCallCount - saves, 1)
        // Filha só ganha histórico de movimentação própria — a cascata não escreve "Movida" nela.
        XCTAssertEqual(stored(child.id).history.count, 1)
    }

    func test_moveTask_saindoDaDone_reabreNaRaiaDestino() async throws {
        let (todo, doing, done) = try lanes()
        let task = try tasks.addTask(title: "Deploy")
        try await sut.moveTask(id: task.id, toLane: done.id)

        try await sut.moveTask(id: task.id, toLane: doing.id)

        XCTAssertNil(stored(task.id).completedAt)
        XCTAssertEqual(stored(task.id).laneID, doing.id)
        XCTAssertEqual(stored(task.id).history.map(\.text),
                       ["Movida: \(todo.title) → Concluído", "Movida: Concluído → Em andamento"])
    }

    /// Filha arrastada para fora da Done reabre o pai concluído (invariante "subtarefa ativa ⇒
    /// pai ativo") — o cartão do pai volta à raia que ele tinha, numa gravação só.
    func test_moveTask_filhaSaindoDaDone_reabreOPai() async throws {
        let (_, doing, done) = try lanes()
        let parent = try tasks.addTask(title: "Apresentação")
        let child = try tasks.addSubtask(parentID: parent.id, title: "Esboço")
        try await sut.moveTask(id: parent.id, toLane: doing.id)
        try await sut.moveTask(id: parent.id, toLane: done.id)
        XCTAssertEqual(stored(child.id).completedAt, now)
        let saves = taskRepo.saveCallCount

        try await sut.moveTask(id: child.id, toLane: doing.id)

        XCTAssertNil(stored(child.id).completedAt)
        XCTAssertNil(stored(parent.id).completedAt)
        XCTAssertEqual(try sut.board().lane(for: stored(parent.id)), doing)
        XCTAssertEqual(taskRepo.saveCallCount - saves, 1)
    }

    func test_moveTask_reaberturaPelaLista_voltaParaRaiaAnterior() async throws {
        let (_, doing, done) = try lanes()
        let task = try tasks.addTask(title: "Deploy")
        try await sut.moveTask(id: task.id, toLane: doing.id)
        try await sut.moveTask(id: task.id, toLane: done.id)

        try await tasks.reopenTask(id: task.id)

        XCTAssertEqual(try sut.board().lane(for: stored(task.id)), doing)
    }

    /// Diária (FEAT-004): o cartão vai para a Done como qualquer outro e o clone para amanhã
    /// nasce na 1ª raia, numa gravação só.
    func test_moveTask_diariaParaDone_concluiECriaCloneNaPrimeiraRaia() async throws {
        let (todo, doing, done) = try lanes()
        let task = try tasks.addTask(title: "Inglês")
        try tasks.setRepeatsDaily(id: task.id, true)
        try await sut.moveTask(id: task.id, toLane: doing.id)
        let savesBefore = taskRepo.saveCallCount

        try await sut.moveTask(id: task.id, toLane: done.id)

        let saved = stored(task.id)
        XCTAssertEqual(saved.completedAt, now)
        XCTAssertEqual(saved.laneID, doing.id, "concluída mantém a raia para reabrir voltar a ela")
        XCTAssertEqual(try sut.board().lane(for: saved), done)
        XCTAssertTrue(saved.history.contains { $0.text == "Movida: Em andamento → Concluído" })
        let clone = try XCTUnwrap(taskRepo.tasks.first { $0.id != task.id && $0.title == "Inglês" })
        XCTAssertNil(clone.completedAt)
        XCTAssertNil(clone.laneID)
        XCTAssertEqual(try sut.board().lane(for: clone), todo)
        XCTAssertTrue(clone.history.isEmpty)
        XCTAssertEqual(taskRepo.saveCallCount, savesBefore + 1)
    }

    // MARK: - Raias

    func test_addRenameMoveLane_gravam() throws {
        try sut.addLane(title: "Revisão")
        var board = try sut.board()
        XCTAssertEqual(board.lanes.map(\.title), ["A fazer", "Em andamento", "Revisão", "Concluído"])

        try sut.renameLane(id: board.lanes[2].id, title: "Em revisão")
        try sut.moveLane(id: board.lanes[2].id, to: 0)
        board = try sut.board()
        XCTAssertEqual(board.lanes.map(\.title), ["Em revisão", "A fazer", "Em andamento", "Concluído"])
    }

    func test_deleteLane_tarefasAbertasVoltamParaPrimeiraComHistorico() async throws {
        let (_, doing, done) = try lanes()
        let open = try tasks.addTask(title: "Aberta")
        let closed = try tasks.addTask(title: "Fechada")
        try await sut.moveTask(id: open.id, toLane: doing.id)
        try await sut.moveTask(id: closed.id, toLane: doing.id)
        try await sut.moveTask(id: closed.id, toLane: done.id)
        XCTAssertEqual(try sut.openTaskCount(inLane: doing.id), 1)

        try sut.deleteLane(id: doing.id)

        let board = try sut.board()
        XCTAssertEqual(board.lanes.map(\.title), ["A fazer", "Concluído"])
        XCTAssertEqual(stored(open.id).laneID, board.firstOpenLane.id)
        XCTAssertEqual(stored(open.id).history.last?.text, "Movida: Em andamento → A fazer (raia removida)")
        XCTAssertNil(stored(closed.id).laneID)
        XCTAssertEqual(stored(closed.id).history.last?.text, "Movida: Em andamento → Concluído")
    }

    /// Apagar a PRIMEIRA raia: as tarefas sem `laneID` estavam nela (regra de `lane(for:)`) e
    /// também precisam ir para a nova primeira raia com histórico — o diálogo prometeu isso.
    func test_deleteLane_primeiraRaia_levaTarefasSemLaneID() async throws {
        let (todo, doing, _) = try lanes()
        let a = try tasks.addTask(title: "A")
        let b = try tasks.addTask(title: "B")
        XCTAssertEqual(try sut.openTaskCount(inLane: todo.id), 2)

        try sut.deleteLane(id: todo.id)

        XCTAssertEqual(try sut.board().lanes.map(\.title), ["Em andamento", "Concluído"])
        for id in [a.id, b.id] {
            XCTAssertEqual(stored(id).laneID, doing.id)
            XCTAssertEqual(stored(id).history.map(\.text), ["Movida: A fazer → Em andamento (raia removida)"])
        }
        XCTAssertEqual(try sut.openTaskCount(inLane: doing.id), 2)
    }

    /// Uma gravação só das tarefas e nada no quadro se ela falhar.
    func test_deleteLane_falhaAoGravarTarefas_naoTocaOQuadro() async throws {
        let (_, doing, _) = try lanes()
        let task = try tasks.addTask(title: "A")
        try await sut.moveTask(id: task.id, toLane: doing.id)
        let savesBefore = boardRepo.saveCount
        taskRepo.saveError = NSError(domain: "disk", code: 1)

        XCTAssertThrowsError(try sut.deleteLane(id: doing.id))

        XCTAssertEqual(boardRepo.saveCount, savesBefore)
        XCTAssertEqual(try sut.board().lanes.count, 3)
        XCTAssertEqual(stored(task.id).laneID, doing.id)
    }

    func test_moveTask_gravaTarefasUmaVezSo() async throws {
        let (_, _, done) = try lanes()
        let task = try tasks.addTask(title: "A")
        let countingRepo = taskRepo!
        let before = countingRepo.saveCallCount

        try await sut.moveTask(id: task.id, toLane: done.id)

        XCTAssertEqual(countingRepo.saveCallCount - before, 1)
        XCTAssertEqual(stored(task.id).completedAt, now)
    }

    func test_deleteLane_doneEUltimaAberta_lancam() throws {
        let (todo, doing, done) = try lanes()
        XCTAssertThrowsError(try sut.deleteLane(id: done.id)) {
            XCTAssertEqual($0 as? DomainError, .cannotDeleteDoneLane)
        }
        try sut.deleteLane(id: doing.id)
        XCTAssertThrowsError(try sut.deleteLane(id: todo.id)) {
            XCTAssertEqual($0 as? DomainError, .cannotDeleteLastOpenLane)
        }
    }

    // MARK: - Configuração do quadro

    func test_setDoneRetentionDays_limitaFaixa() throws {
        XCTAssertEqual(try sut.setDoneRetentionDays(0).doneRetentionDays, 1)
        XCTAssertEqual(try sut.setDoneRetentionDays(120).doneRetentionDays, 90)
        XCTAssertEqual(try sut.setDoneRetentionDays(14).doneRetentionDays, 14)
        XCTAssertEqual(boardRepo.board?.doneRetentionDays, 14)
    }

    func test_setTaskScope_normalizaTags() throws {
        let board = try sut.setTaskScope(.tags([" Trabalho ", "trabalho", "", "Estudo"]))
        XCTAssertEqual(board.taskScope, .tags(["Trabalho", "Estudo"]))
    }

    func test_renameEDeleteTag_atualizamEscopoDoQuadro() throws {
        _ = try tasks.addTask(title: "A", tags: ["Trabalho", "Casa"])
        try sut.setTaskScope(.tags(["Trabalho", "Casa"]))

        try tasks.renameTag(from: "trabalho", to: "Job")
        XCTAssertEqual(try sut.board().taskScope, .tags(["Job", "Casa"]))

        try tasks.deleteTag("Casa")
        try tasks.deleteTag("Job")
        XCTAssertEqual(try sut.board().taskScope, .tags([]))
    }

    func test_renameTag_semQuadro_naoQuebra() throws {
        let plain = ManageTasksUseCase(tasks: taskRepo, importer: importer, now: { self.now })
        _ = try plain.addTask(title: "A", tags: ["x"])
        XCTAssertNoThrow(try plain.renameTag(from: "x", to: "y"))
        XCTAssertNoThrow(try plain.deleteTag("y"))
    }
}
