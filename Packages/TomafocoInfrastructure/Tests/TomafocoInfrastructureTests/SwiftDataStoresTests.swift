import XCTest
import SwiftData
import TomafocoDomain
@testable import TomafocoInfrastructure

/// Stores SwiftData (FEAT-006) contra banco em memória: fidelidade do mapeamento, diff do
/// `saveTasks`, histórico por inserção e transação com rollback.
@MainActor
final class SwiftDataStoresTests: XCTestCase {

    private var database: TomafocoDatabase!

    override func setUp() async throws {
        database = try TomafocoDatabase.inMemory()
    }

    private func taskRows() throws -> [TaskRecord] {
        try database.context.fetch(FetchDescriptor<TaskRecord>())
    }

    /// Tarefa com TODOS os campos preenchidos — o mapeamento não pode perder nenhum.
    private func richTask(title: String = "Completa") -> FocusTask {
        FocusTask(
            id: UUID(), title: title, source: .reminders, reminderID: "rem-1",
            createdAt: Date(timeIntervalSince1970: 1_800_000_000.123),
            completedAt: Date(timeIntervalSince1970: 1_800_100_000.5),
            tags: ["Trabalho", "Casa"], notes: "nota", dueDate: Date(timeIntervalSince1970: 1_800_200_000),
            priority: 1, sourceURL: "https://globo.com",
            history: [TaskHistoryEntry(id: UUID(), createdAt: Date(timeIntervalSince1970: 1_800_000_500), text: "h")],
            repeatsDaily: true, completionLog: [Date(timeIntervalSince1970: 1_799_000_000)],
            laneID: UUID(), isUrgent: true, parentID: UUID())
    }

    private func task(_ title: String) -> FocusTask {
        FocusTask(id: UUID(), title: title, source: .manual, createdAt: Date(timeIntervalSince1970: 1_000))
    }

    // MARK: - Tarefas

    func test_tarefas_roundTripFielDeTodosOsCampos_inclusiveFracaoDeSegundo() throws {
        let original = richTask()
        try SwiftDataTaskStore(database: database).saveTasks([original])
        // Store novo = sem espelho: lê de verdade do banco.
        XCTAssertEqual(try SwiftDataTaskStore(database: database).loadTasks(), [original])
    }

    func test_tarefas_preservaOrdem() throws {
        let tasks = (1...5).map { task("T\($0)") }
        try SwiftDataTaskStore(database: database).saveTasks(tasks)
        XCTAssertEqual(try SwiftDataTaskStore(database: database).loadTasks().map(\.title), ["T1", "T2", "T3", "T4", "T5"])
    }

    func test_saveTasks_apagaAsQueSumiram_eAtualizaSoAsAlteradas() throws {
        let store = SwiftDataTaskStore(database: database)
        let a = task("A"), c = task("C")
        var b = task("B")
        try store.saveTasks([a, b, c])
        let payloadA = try taskRows().first { $0.id == a.id }!.payload

        b.title = "B2"
        try store.saveTasks([a, b])

        XCTAssertEqual(try SwiftDataTaskStore(database: database).loadTasks().map(\.title), ["A", "B2"])
        XCTAssertEqual(try taskRows().count, 2)
        XCTAssertEqual(try taskRows().first { $0.id == a.id }!.payload, payloadA, "inalterada não é regravada")
    }

    /// Achado do review: reordenar pelo `saveTasks` precisa sobreviver à reabertura.
    func test_saveTasks_reordenacaoPersiste() throws {
        let store = SwiftDataTaskStore(database: database)
        let a = task("A"), b = task("B"), c = task("C")
        try store.saveTasks([a, b, c])
        try store.saveTasks([c, a, b])
        XCTAssertEqual(try SwiftDataTaskStore(database: database).loadTasks().map(\.title), ["C", "A", "B"])
        // E uma inserção depois continua no fim.
        try store.upsert([task("D")])
        XCTAssertEqual(try SwiftDataTaskStore(database: database).loadTasks().map(\.title), ["C", "A", "B", "D"])
    }

    func test_upsert_atualizaUma_eInsereNova() throws {
        let store = SwiftDataTaskStore(database: database)
        var a = task("A")
        try store.saveTasks([a, task("B")])
        a.isUrgent = true
        let nova = task("Nova")
        try store.upsert([a, nova])

        let fresh = SwiftDataTaskStore(database: database)
        XCTAssertEqual(try fresh.loadTasks().map(\.title), ["A", "B", "Nova"])
        XCTAssertEqual(try fresh.task(id: a.id)?.isUrgent, true)
        XCTAssertNil(try fresh.task(id: UUID()))
    }

    func test_colunasDeBusca_acompanhamOPayload() throws {
        let store = SwiftDataTaskStore(database: database)
        var a = task("A")
        try store.saveTasks([a])
        a.completedAt = Date(timeIntervalSince1970: 5_000)
        a.dueDate = Date(timeIntervalSince1970: 6_000)
        try store.upsert([a])
        let row = try XCTUnwrap(try taskRows().first)
        XCTAssertEqual(row.completedAt, a.completedAt)
        XCTAssertEqual(row.dueDate, a.dueDate)
    }

    /// Linha com payload ilegível não some da base por causa do diff do `saveTasks`.
    func test_payloadIlegivel_naoEApagadoPeloDiff() throws {
        let bad = TaskRecord(id: UUID(), position: 0, createdAt: Date(), completedAt: nil, dueDate: nil,
                             parentID: nil, payload: Data("lixo".utf8))
        database.context.insert(bad)
        try database.context.save()

        let store = SwiftDataTaskStore(database: database)
        XCTAssertEqual(try store.loadTasks(), [])
        try store.saveTasks([task("A")])
        XCTAssertEqual(try taskRows().count, 2)
    }

    // MARK: - Transação

    func test_perform_erroDesfazTudo_eEspelhoReleBanco() throws {
        let store = SwiftDataTaskStore(database: database)
        try store.saveTasks([task("A")])
        struct Boom: Error {}
        XCTAssertThrowsError(try database.perform {
            try store.upsert([task("B")])
            throw Boom()
        })
        XCTAssertEqual(try store.loadTasks().map(\.title), ["A"])
        XCTAssertEqual(try SwiftDataTaskStore(database: database).loadTasks().map(\.title), ["A"])
    }

    func test_perform_gravaNoFim() throws {
        let store = SwiftDataTaskStore(database: database)
        try database.perform {
            try store.upsert([task("A")])
            try store.upsert([task("B")])
            XCTAssertTrue(database.context.hasChanges, "dentro da transação nada foi gravado ainda")
        }
        XCTAssertFalse(database.context.hasChanges)
        XCTAssertEqual(try SwiftDataTaskStore(database: database).loadTasks().map(\.title), ["A", "B"])
    }

    /// Achado do review: bloco interno que falha condena a transação externa — mesmo capturado.
    func test_performAninhado_falhaInterna_desfazTudo() throws {
        let store = SwiftDataTaskStore(database: database)
        try store.saveTasks([task("A")])
        struct Boom: Error {}
        XCTAssertThrowsError(try database.perform {
            try store.upsert([task("B")])
            _ = try? database.perform {
                try store.upsert([task("C")])
                throw Boom()
            }
        }) { XCTAssertEqual($0 as? TomafocoDatabase.TransactionError, .aborted) }
        XCTAssertEqual(try SwiftDataTaskStore(database: database).loadTasks().map(\.title), ["A"])
        // A sessão continua gravando depois disso (profundidade não ficou torta).
        try store.upsert([task("D")])
        XCTAssertFalse(database.context.hasChanges)
        XCTAssertEqual(try SwiftDataTaskStore(database: database).loadTasks().map(\.title), ["A", "D"])
    }

    // MARK: - Sessões

    private func record(_ offset: TimeInterval) -> SessionRecord {
        SessionRecord(sessionID: UUID(), phase: .focus, startedAt: Date(timeIntervalSince1970: offset),
                      endedAt: Date(timeIntervalSince1970: offset + 1_500), outcome: .completed,
                      cycleNumber: 1, taskIDs: [UUID()])
    }

    func test_historico_insereEmOrdem() throws {
        let store = SwiftDataSessionStore(database: database)
        let records = [record(300), record(100), record(200)]
        try records.forEach { try store.appendToHistory($0) }
        XCTAssertEqual(try SwiftDataSessionStore(database: database).loadHistory(), records)
    }

    func test_sessaoAtiva_salvaLeLimpa() throws {
        let store = SwiftDataSessionStore(database: database)
        XCTAssertNil(try store.loadActive())
        let session = PomodoroSession(id: UUID(), phase: .focus, startedAt: Date(timeIntervalSince1970: 10),
                                      endsAt: Date(timeIntervalSince1970: 1_510), cycleNumber: 2, taskIDs: [UUID()])
        try store.saveActive(session)
        XCTAssertEqual(try SwiftDataSessionStore(database: database).loadActive(), session)
        XCTAssertFalse(database.context.hasChanges, "failsafe grava na hora")
        try store.clearActive()
        XCTAssertNil(try store.loadActive())
    }

    // MARK: - Quadro e tags

    func test_quadro_roundTrip() throws {
        let store = SwiftDataKanbanStore(database: database)
        XCTAssertNil(try store.loadBoard())
        let board = KanbanBoard.makeDefault(makeID: { UUID() })
        try store.saveBoard(board)
        XCTAssertEqual(try SwiftDataKanbanStore(database: database).loadBoard(), board)
    }

    func test_tags_preservaOrdem_eSubstitui() throws {
        let catalog = SwiftDataTagCatalog(database: database)
        catalog.saveTags(["b", "a", "c"])
        XCTAssertEqual(SwiftDataTagCatalog(database: database).loadTags(), ["b", "a", "c"])
        catalog.saveTags(["c", "d"])
        XCTAssertEqual(SwiftDataTagCatalog(database: database).loadTags(), ["c", "d"])
    }

    // MARK: - Projetos

    func test_projetos_roundTrip_atualiza_apaga() throws {
        let store = SwiftDataProjectStore(database: database)
        var project = Project(id: UUID(), title: "Site", createdAt: Date(timeIntervalSince1970: 1_000.5),
                              dueDate: Date(timeIntervalSince1970: 86_400), color: .orange, icon: "hammer",
                              details: "d")
        try store.upsert(project)
        XCTAssertEqual(try SwiftDataProjectStore(database: database).loadProjects(), [project])

        project.title = "Site 2"
        try store.upsert(project)
        XCTAssertEqual(try store.loadProjects(), [project])

        try store.delete(id: project.id)
        XCTAssertEqual(try store.loadProjects(), [])
    }

    /// Apagar projeto + tirar das tarefas: erro no meio desfaz as duas coisas.
    func test_unitOfWork_projetoETarefas_rollback() throws {
        let projects = SwiftDataProjectStore(database: database)
        let tasks = SwiftDataTaskStore(database: database)
        let project = Project(id: UUID(), title: "P", createdAt: Date())
        try projects.upsert(project)
        var t = task("A"); t.projectID = project.id
        try tasks.saveTasks([t])
        struct Boom: Error {}

        XCTAssertThrowsError(try database.perform {
            var cleared = t; cleared.projectID = nil
            try tasks.saveTasks([cleared])
            try projects.delete(id: project.id)
            throw Boom()
        })

        XCTAssertEqual(try projects.loadProjects(), [project])
        XCTAssertEqual(try tasks.task(id: t.id)?.projectID, project.id)
    }

    // MARK: - Banco em disco

    func test_storeCorrompido_viraBak_eAbreVazio() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tomafoco-db-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("Tomafoco.store")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("isto não é sqlite".utf8).write(to: url)

        let db = try TomafocoDatabase.open(at: url, retryDelay: 0)
        XCTAssertTrue(db.wasReset)
        XCTAssertEqual(try SwiftDataTaskStore(database: db).loadTasks(), [])
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertTrue(names.contains { $0.hasPrefix("Tomafoco.store.bak-") }, "\(names)")
    }

    /// Achado do review: a tentativa anterior renomeou para `.bak` e morreu antes de criar o
    /// novo — nesta abertura o banco nasce do zero, mas o usuário ainda precisa do aviso.
    func test_bancoNovoComBakAoLado_contaComoReset() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tomafoco-db-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: dir.appendingPathComponent("Tomafoco.store.bak-2026-10-29"))

        let db = try TomafocoDatabase.open(at: dir.appendingPathComponent("Tomafoco.store"), retryDelay: 0)
        XCTAssertTrue(db.wasReset)
        // Na abertura seguinte o banco já existe: não é mais reset.
        XCTAssertFalse(try TomafocoDatabase.open(at: dir.appendingPathComponent("Tomafoco.store"), retryDelay: 0).wasReset)
    }

    func test_bancoEmDisco_persisteEntreAberturas() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tomafoco-db-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("Tomafoco.store")
        let original = richTask()
        do {
            let db = try TomafocoDatabase.open(at: url, retryDelay: 0)
            try SwiftDataTaskStore(database: db).saveTasks([original])
        }
        let reopened = try TomafocoDatabase.open(at: url, retryDelay: 0)
        XCTAssertFalse(reopened.wasReset)
        XCTAssertEqual(try SwiftDataTaskStore(database: reopened).loadTasks(), [original])
    }
}
