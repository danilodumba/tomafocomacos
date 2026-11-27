import XCTest
import TomafocoDomain
import TomafocoTestSupport
@testable import TomafocoApplication

/// Códigos de tarefa por projeto (RF-09.22): "PSC" + número com 4 dígitos, contador no projeto.
@MainActor
final class TaskCodeTests: XCTestCase {

    private var taskRepo: InMemoryTaskRepository!
    private var projectRepo: InMemoryProjectRepository!
    private var unitOfWork: InMemoryUnitOfWork!
    private var projects: ManageProjectsUseCase!
    private var sut: ManageTasksUseCase!
    private let now = Date(timeIntervalSince1970: 1_900_000_000)

    private struct Boom: Error {}

    override func setUp() async throws {
        taskRepo = InMemoryTaskRepository()
        projectRepo = InMemoryProjectRepository()
        unitOfWork = InMemoryUnitOfWork(tasks: taskRepo, projects: projectRepo)
        projects = ManageProjectsUseCase(projects: projectRepo, tasks: taskRepo, unitOfWork: unitOfWork,
                                         now: { self.now })
        sut = ManageTasksUseCase(tasks: taskRepo, importer: StubTaskImporter(), now: { self.now },
                                 projects: projectRepo, unitOfWork: unitOfWork)
    }

    private func project(_ code: String?, start: Int = 1, title: String = "PSC") throws -> Project {
        try projects.addProject(ProjectDraft(title: title, code: code, nextCodeNumber: start))
    }

    private func counter(_ id: UUID) -> Int? { projectRepo.projects.first { $0.id == id }?.nextCodeNumber }
    private func stored(_ id: UUID) -> FocusTask? { taskRepo.tasks.first { $0.id == id } }

    // MARK: - Projeto

    func test_projeto_codigoNormalizado_limite_eUnico() throws {
        let p = try project("  psc ", start: 0)
        XCTAssertEqual(p.code, "PSC")
        XCTAssertEqual(p.nextCodeNumber, 1, "número inicial mínimo 1")
        XCTAssertThrowsError(try project("ABCDEF", title: "Outro")) {
            XCTAssertEqual($0 as? DomainError, .invalidProjectCode(maxLength: 5))
        }
        XCTAssertThrowsError(try project("P SC", title: "Outro")) {
            XCTAssertEqual($0 as? DomainError, .invalidProjectCode(maxLength: 5))
        }
        XCTAssertThrowsError(try project("Psc", title: "Outro")) {
            XCTAssertEqual($0 as? DomainError, .duplicateProjectCode("PSC"))
        }
        XCTAssertNil(try project("   ", title: "Sem código").code)
    }

    func test_formato_quatroDigitos() {
        XCTAssertEqual(Project.taskCode(prefix: "PSC", number: 1), "PSC0001")
        XCTAssertEqual(Project.taskCode(prefix: "PSC", number: 123), "PSC0123")
        XCTAssertEqual(Project.taskCode(prefix: "PSC", number: 12345), "PSC12345")
    }

    // MARK: - Criar

    func test_criarNoProjeto_geraCodigoEAvancaContador() throws {
        let p = try project("PSC")
        let a = try sut.addTask(title: "A", projectID: p.id)
        let b = try sut.addTask(title: "B", projectID: p.id)
        XCTAssertEqual(a.code, "PSC0001")
        XCTAssertEqual(b.code, "PSC0002")
        XCTAssertEqual(b.displayTitle, "PSC0002 - B")
        XCTAssertEqual(counter(p.id), 3)
    }

    func test_numeroInicialDoProjeto() throws {
        let p = try project("PSC", start: 40)
        XCTAssertEqual(try sut.addTask(title: "A", projectID: p.id).code, "PSC0040")
    }

    func test_projetoSemCodigo_ouSemProjeto_naoFazNada() throws {
        let p = try project(nil)
        XCTAssertNil(try sut.addTask(title: "A", projectID: p.id).code)
        XCTAssertNil(try sut.addTask(title: "B").code)
        XCTAssertEqual(counter(p.id), 1)
    }

    func test_subtarefaNaoGeraCodigo() throws {
        let p = try project("PSC")
        let parent = try sut.addTask(title: "Pai", projectID: p.id)
        let child = try sut.addSubtask(parentID: parent.id, title: "Filha")
        XCTAssertNil(child.code)
        XCTAssertEqual(counter(p.id), 2)
    }

    func test_lote_codigosEmSequencia() throws {
        let p = try project("PSC")
        let created = try sut.addTasks([NewTaskDraft(title: "A", projectID: p.id), NewTaskDraft(title: "B"),
                                        NewTaskDraft(title: "C", projectID: p.id)])
        XCTAssertEqual(created.map(\.code), ["PSC0001", nil, "PSC0002"])
        XCTAssertEqual(counter(p.id), 3)
    }

    /// Contador e tarefa vão juntos: falhou a gravação → nem tarefa nem número gasto.
    func test_falhaAoGravar_naoGastaNumero() throws {
        let p = try project("PSC")
        taskRepo.saveError = Boom()
        XCTAssertThrowsError(try sut.addTask(title: "A", projectID: p.id))
        XCTAssertEqual(counter(p.id), 1)
    }

    // MARK: - Associar (editar)

    func test_associarAoProjeto_geraCodigo_reeditarNaoGeraDeNovo() throws {
        let p = try project("PSC")
        let task = try sut.addTask(title: "A")
        _ = try sut.editTask(id: task.id, TaskEdit(title: "A", projectID: p.id))
        XCTAssertEqual(stored(task.id)?.code, "PSC0001")
        _ = try sut.editTask(id: task.id, TaskEdit(title: "A2", projectID: p.id, code: "PSC0001"))
        XCTAssertEqual(stored(task.id)?.code, "PSC0001")
        XCTAssertEqual(counter(p.id), 2)
    }

    func test_trocarDeProjeto_geraCodigoDoNovo_semCodigoMantemOAntigo() throws {
        let psc = try project("PSC")
        let erp = try project("ERP", title: "ERP")
        let plain = try project(nil, title: "Sem")
        let task = try sut.addTask(title: "A", projectID: psc.id)
        _ = try sut.editTask(id: task.id, TaskEdit(title: "A", projectID: erp.id, code: "PSC0001"))
        XCTAssertEqual(stored(task.id)?.code, "ERP0001")
        _ = try sut.editTask(id: task.id, TaskEdit(title: "A", projectID: plain.id, code: "ERP0001"))
        XCTAssertEqual(stored(task.id)?.code, "ERP0001", "projeto sem código: não faz nada")
    }

    func test_codigoDigitado_venceOGerado() throws {
        let p = try project("PSC")
        let task = try sut.addTask(title: "A")
        _ = try sut.editTask(id: task.id, TaskEdit(title: "A", projectID: p.id, code: "  X-99 "))
        XCTAssertEqual(stored(task.id)?.code, "X-99")
        XCTAssertEqual(counter(p.id), 1, "não gastou número")
        _ = try sut.editTask(id: task.id, TaskEdit(title: "A", projectID: p.id, code: ""))
        XCTAssertNil(stored(task.id)?.code)
    }

    func test_edicaoCurta_preservaCodigo() throws {
        let p = try project("PSC")
        let task = try sut.addTask(title: "A", projectID: p.id)
        _ = try sut.editTask(id: task.id, title: "A2", tags: [], dueDate: nil, priority: .none)
        XCTAssertEqual(stored(task.id)?.code, "PSC0001")
    }

    // MARK: - Duplicar / repetir

    func test_duplicar_incrementaCodigo_filhasSemCodigo() throws {
        let p = try project("PSC")
        let parent = try sut.addTask(title: "A", projectID: p.id)
        _ = try sut.addSubtask(parentID: parent.id, title: "F")
        let copy = try XCTUnwrap(try sut.duplicateTask(id: parent.id))
        XCTAssertEqual(copy.code, "PSC0002")
        XCTAssertEqual(counter(p.id), 3)
        XCTAssertTrue(taskRepo.tasks.filter { $0.parentID == copy.id }.allSatisfy { $0.code == nil })
    }

    func test_duplicar_semCodigoNoProjeto_copiaSemCodigo() throws {
        let task = try sut.addTask(title: "A")
        _ = try sut.editTask(id: task.id, TaskEdit(title: "A", code: "MEU-1"))
        XCTAssertNil(try sut.duplicateTask(id: task.id)?.code)
    }

    func test_repetir_cloneMantemCodigo() async throws {
        let p = try project("PSC")
        let task = try sut.addTask(title: "A", projectID: p.id)
        try sut.setRecurrence(id: task.id, .everyDay)
        try await sut.completeTask(id: task.id)
        let clone = try XCTUnwrap(taskRepo.tasks.first { $0.id != task.id })
        XCTAssertEqual(clone.code, "PSC0001")
        XCTAssertEqual(counter(p.id), 2)
    }

    func test_buscaPeloCodigo() throws {
        let p = try project("PSC")
        let task = try sut.addTask(title: "Relatório", projectID: p.id)
        XCTAssertTrue(TaskFilter(searchText: "psc0001").matchesTree(task, children: [], now: now, calendar: .current))
        XCTAssertFalse(TaskFilter(searchText: "PSC0002").matchesTree(task, children: [], now: now, calendar: .current))
    }
}
