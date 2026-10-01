import XCTest
import TomafocoDomain
import TomafocoTestSupport
@testable import TomafocoApplication

/// Criação de tarefas em lote (RF-09.8): texto → grid → `addTasks`.
final class ManageTasksBulkAddTests: XCTestCase {

    private var repo: InMemoryTaskRepository!
    private var sut: ManageTasksUseCase!
    private let now = Date(timeIntervalSince1970: 1_000_000)

    override func setUp() {
        super.setUp()
        repo = InMemoryTaskRepository()
        sut = ManageTasksUseCase(tasks: repo, importer: StubTaskImporter(), now: { self.now })
    }

    func test_addTasks_criaTodasComCamposDoGrid() throws {
        let due = Date(timeIntervalSince1970: 2_000_000)
        let created = try sut.addTasks([
            NewTaskDraft(title: "  Revisar PR ", tags: ["Trabalho", "trabalho"], dueDate: due, priority: .high),
            NewTaskDraft(title: "Pagar boleto")
        ])

        XCTAssertEqual(created.map(\.title), ["Revisar PR", "Pagar boleto"])
        let saved = try repo.loadTasks()
        XCTAssertEqual(saved.count, 2)
        XCTAssertEqual(saved[0].tags, ["Trabalho"])
        XCTAssertEqual(saved[0].dueDate, due)
        XCTAssertEqual(saved[0].priority, 1)
        XCTAssertEqual(saved[0].source, .manual)
        XCTAssertEqual(saved[0].createdAt, now)
        XCTAssertNil(saved[1].dueDate)
        XCTAssertNil(saved[1].priority)
    }

    func test_addTasks_preservaTarefasExistentes() throws {
        try sut.addTask(title: "Antiga")
        try sut.addTasks([NewTaskDraft(title: "Nova")])
        XCTAssertEqual(try repo.loadTasks().map(\.title), ["Antiga", "Nova"])
    }

    func test_addTasks_loteVazio_naoGrava() throws {
        repo.saveError = NSError(domain: "x", code: 1)
        XCTAssertEqual(try sut.addTasks([]), [])
    }

    /// Atômico: um rascunho inválido barra o lote inteiro — nada é gravado.
    func test_addTasks_umInvalido_naoGravaNenhuma() throws {
        XCTAssertThrowsError(try sut.addTasks([
            NewTaskDraft(title: "Válida"),
            NewTaskDraft(title: "   ")
        ])) { error in
            XCTAssertEqual(error as? DomainError, .emptyTaskTitle)
        }
        XCTAssertTrue(repo.tasks.isEmpty)
    }

    func test_addTasks_duplicataDentroDoLote_lanca() {
        XCTAssertThrowsError(try sut.addTasks([
            NewTaskDraft(title: "Estudar"),
            NewTaskDraft(title: "ESTUDAR")
        ])) { error in
            XCTAssertEqual(error as? DomainError, .duplicateEntry("ESTUDAR"))
        }
        XCTAssertTrue(repo.tasks.isEmpty)
    }

    func test_addTasks_duplicataDeAtiva_lanca() throws {
        try sut.addTask(title: "Reunião")
        XCTAssertThrowsError(try sut.addTasks([NewTaskDraft(title: "reunião")]))
        XCTAssertEqual(repo.tasks.count, 1)
    }

    /// Mesma regra do `addTask`: título de tarefa concluída fica livre.
    func test_addTasks_tituloIgualAoDeConcluida_permite() async throws {
        let done = try sut.addTask(title: "Reunião")
        try await sut.completeTask(id: done.id)
        XCTAssertNoThrow(try sut.addTasks([NewTaskDraft(title: "Reunião")]))
    }

    func test_addTasks_tagsEntramNoCatalogo() throws {
        let created = try sut.addTasks([NewTaskDraft(title: "A", tags: ["Faturamento"])])
        try sut.deleteTask(id: created[0].id)
        XCTAssertEqual(try sut.allTags(), ["Faturamento"])
    }

    func test_validateNewTasks_apontaIndicesDasLinhasComProblema() throws {
        try sut.addTask(title: "Existente")
        let issues = try sut.validateNewTasks([
            NewTaskDraft(title: "Ok"),
            NewTaskDraft(title: ""),
            NewTaskDraft(title: "existente"),
            NewTaskDraft(title: "Ok"),
            NewTaskDraft(title: "Outra")
        ])
        // A 1ª ocorrência de "Ok" é válida; a repetição é que acusa.
        XCTAssertEqual(issues, [1: .emptyTaskTitle, 2: .duplicateEntry("existente"), 3: .duplicateEntry("Ok")])
    }
}
