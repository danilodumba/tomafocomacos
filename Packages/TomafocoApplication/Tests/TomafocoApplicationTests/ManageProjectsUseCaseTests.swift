import XCTest
import TomafocoDomain
import TomafocoTestSupport
@testable import TomafocoApplication

/// Projetos (FEAT-006): cadastro, vínculo nas tarefas, herança na subtarefa e filtro.
@MainActor
final class ManageProjectsUseCaseTests: XCTestCase {

    private var taskRepo: InMemoryTaskRepository!
    private var projectRepo: InMemoryProjectRepository!
    private var unitOfWork: InMemoryUnitOfWork!
    private var sut: ManageProjectsUseCase!
    private var tasks: ManageTasksUseCase!
    private var calendar: Calendar!
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUp() async throws {
        taskRepo = InMemoryTaskRepository()
        projectRepo = InMemoryProjectRepository()
        unitOfWork = InMemoryUnitOfWork(tasks: taskRepo, projects: projectRepo)
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Sao_Paulo")!
        sut = ManageProjectsUseCase(projects: projectRepo, tasks: taskRepo, unitOfWork: unitOfWork,
                                    now: { self.now }, calendar: calendar)
        tasks = ManageTasksUseCase(tasks: taskRepo, importer: StubTaskImporter(), now: { self.now },
                                   projects: projectRepo)
    }

    // MARK: - Cadastro

    func test_addProject_normaliza_eGuardaCadastro() throws {
        let due = calendar.date(from: DateComponents(year: 2026, month: 11, day: 3, hour: 15))!
        let project = try sut.addProject(ProjectDraft(title: "  Site novo ", dueDate: due, color: .purple,
                                                      icon: "briefcase", details: "  \n "))
        XCTAssertEqual(project.title, "Site novo")
        XCTAssertEqual(project.createdAt, now)
        XCTAssertEqual(project.dueDate, calendar.startOfDay(for: due), "prazo é um dia — hora descartada")
        XCTAssertEqual(project.color, .purple)
        XCTAssertEqual(project.icon, "briefcase")
        XCTAssertNil(project.details, "descrição em branco vira nil")
        XCTAssertEqual(projectRepo.projects, [project])
    }

    func test_addProject_tituloVazio() {
        XCTAssertThrowsError(try sut.addProject(ProjectDraft(title: "   "))) {
            XCTAssertEqual($0 as? DomainError, .emptyProjectTitle)
        }
    }

    func test_addProject_duplicataSemCaixa() throws {
        try sut.addProject(ProjectDraft(title: "Site"))
        XCTAssertThrowsError(try sut.addProject(ProjectDraft(title: "SITE"))) {
            XCTAssertEqual($0 as? DomainError, .duplicateProject("SITE"))
        }
    }

    func test_editProject_mesmoTitulo_naoAcusaDuplicata_eMantemCadastro() throws {
        let project = try sut.addProject(ProjectDraft(title: "Site"))
        let edited = try sut.editProject(id: project.id, ProjectDraft(title: "site", color: .green, details: "x"))
        XCTAssertEqual(edited.title, "site")
        XCTAssertEqual(edited.color, .green)
        XCTAssertEqual(edited.details, "x")
        XCTAssertEqual(edited.createdAt, project.createdAt)
    }

    func test_editProject_tituloDeOutro_acusaDuplicata() throws {
        try sut.addProject(ProjectDraft(title: "A"))
        let b = try sut.addProject(ProjectDraft(title: "B"))
        XCTAssertThrowsError(try sut.editProject(id: b.id, ProjectDraft(title: "a"))) {
            XCTAssertEqual($0 as? DomainError, .duplicateProject("a"))
        }
    }

    func test_editProject_inexistente() {
        XCTAssertThrowsError(try sut.editProject(id: UUID(), ProjectDraft(title: "X"))) {
            XCTAssertEqual($0 as? DomainError, .projectNotFound)
        }
    }

    func test_allProjects_ordemNaturalPorTitulo() throws {
        for title in ["b", "Projeto 10", "a", "Projeto 2"] { try sut.addProject(ProjectDraft(title: title)) }
        XCTAssertEqual(try sut.allProjects().map(\.title), ["a", "b", "Projeto 2", "Projeto 10"])
    }

    // MARK: - Apagar

    func test_deleteProject_tiraVinculoDeAbertasEConcluidas_numaTransacao() throws {
        let project = try sut.addProject(ProjectDraft(title: "Site"))
        let other = try sut.addProject(ProjectDraft(title: "Outro"))
        let a = try tasks.addTask(title: "A", projectID: project.id)
        let b = try tasks.addTask(title: "B", projectID: project.id)
        let c = try tasks.addTask(title: "C", projectID: other.id)
        _ = try tasks.update(id: b.id) { $0.completedAt = self.now }

        XCTAssertEqual(try sut.taskCount(of: project.id), 2)
        let affected = try sut.deleteProject(id: project.id)

        XCTAssertEqual(affected, 2)
        XCTAssertEqual(unitOfWork.performCount, 1)
        XCTAssertEqual(projectRepo.projects.map(\.id), [other.id])
        XCTAssertNil(try taskRepo.task(id: a.id)?.projectID)
        XCTAssertNil(try taskRepo.task(id: b.id)?.projectID)
        XCTAssertEqual(try taskRepo.task(id: c.id)?.projectID, other.id)
        XCTAssertEqual(taskRepo.tasks.count, 3, "não apaga tarefa")
    }

    func test_deleteProject_falhaNoMeio_desfazTudo() throws {
        let project = try sut.addProject(ProjectDraft(title: "Site"))
        let a = try tasks.addTask(title: "A", projectID: project.id)
        struct Boom: Error {}
        projectRepo.saveError = Boom()

        XCTAssertThrowsError(try sut.deleteProject(id: project.id))

        XCTAssertEqual(try taskRepo.task(id: a.id)?.projectID, project.id, "vínculo restaurado")
        XCTAssertEqual(projectRepo.projects.map(\.id), [project.id])
    }

    func test_openTaskCounts_soAbertas() throws {
        let project = try sut.addProject(ProjectDraft(title: "Site"))
        try tasks.addTask(title: "A", projectID: project.id)
        let b = try tasks.addTask(title: "B", projectID: project.id)
        _ = try tasks.update(id: b.id) { $0.completedAt = self.now }
        try tasks.addTask(title: "Sem")
        XCTAssertEqual(try sut.openTaskCounts(), [project.id: 1])
    }

    // MARK: - Vínculo nas tarefas

    func test_addTask_projetoInexistente() {
        XCTAssertThrowsError(try tasks.addTask(title: "A", projectID: UUID())) {
            XCTAssertEqual($0 as? DomainError, .projectNotFound)
        }
        XCTAssertTrue(taskRepo.tasks.isEmpty)
    }

    func test_addSubtask_herdaProjetoDoPai() throws {
        let project = try sut.addProject(ProjectDraft(title: "Site"))
        let pai = try tasks.addTask(title: "Pai", projectID: project.id)
        let filha = try tasks.addSubtask(parentID: pai.id, title: "Filha")
        XCTAssertEqual(filha.projectID, project.id)
    }

    func test_editTask_projetoDoPai_propagaAsFilhas() throws {
        let p1 = try sut.addProject(ProjectDraft(title: "P1"))
        let p2 = try sut.addProject(ProjectDraft(title: "P2"))
        let pai = try tasks.addTask(title: "Pai", projectID: p1.id)
        let filha = try tasks.addSubtask(parentID: pai.id, title: "Filha")
        let saves = taskRepo.saveCallCount

        try tasks.editTask(id: pai.id, TaskEdit(title: "Pai", projectID: p2.id))

        XCTAssertEqual(try taskRepo.task(id: pai.id)?.projectID, p2.id)
        XCTAssertEqual(try taskRepo.task(id: filha.id)?.projectID, p2.id)
        XCTAssertEqual(taskRepo.saveCallCount, saves + 1, "pai e filhas numa gravação")
    }

    func test_editTask_subtarefa_ignoraProjetoRecebido() throws {
        let p1 = try sut.addProject(ProjectDraft(title: "P1"))
        let p2 = try sut.addProject(ProjectDraft(title: "P2"))
        let pai = try tasks.addTask(title: "Pai", projectID: p1.id)
        let filha = try tasks.addSubtask(parentID: pai.id, title: "Filha")

        try tasks.editTask(id: filha.id, TaskEdit(title: "Filha", projectID: p2.id))

        XCTAssertEqual(try taskRepo.task(id: filha.id)?.projectID, p1.id)
    }

    func test_editTask_projetoApagadoEmOutraJanela() throws {
        let project = try sut.addProject(ProjectDraft(title: "Site"))
        let task = try tasks.addTask(title: "A")
        try sut.deleteProject(id: project.id)
        XCTAssertThrowsError(try tasks.editTask(id: task.id, TaskEdit(title: "A", projectID: project.id))) {
            XCTAssertEqual($0 as? DomainError, .projectNotFound)
        }
    }

    /// A forma curta (edição parcial) não pode tirar a tarefa do projeto.
    func test_editTaskFormaCurta_preservaProjeto() throws {
        let project = try sut.addProject(ProjectDraft(title: "Site"))
        let task = try tasks.addTask(title: "A", projectID: project.id)
        try tasks.editTask(id: task.id, title: "A2", tags: [], dueDate: nil, priority: .none)
        XCTAssertEqual(try taskRepo.task(id: task.id)?.projectID, project.id)
    }

    func test_makeSubtask_assumeProjetoDoNovoPai() throws {
        let p1 = try sut.addProject(ProjectDraft(title: "P1"))
        let pai = try tasks.addTask(title: "Pai", projectID: p1.id)
        let solta = try tasks.addTask(title: "Solta")
        let virou = try tasks.makeSubtask(id: solta.id, parentID: pai.id)
        XCTAssertEqual(virou?.projectID, p1.id)
    }

    func test_addTasks_lote_comProjeto() throws {
        let project = try sut.addProject(ProjectDraft(title: "Site"))
        let created = try tasks.addTasks([NewTaskDraft(title: "A", projectID: project.id), NewTaskDraft(title: "B")])
        XCTAssertEqual(created.map(\.projectID), [project.id, nil])
        XCTAssertThrowsError(try tasks.addTasks([NewTaskDraft(title: "C", projectID: UUID())])) {
            XCTAssertEqual($0 as? DomainError, .projectNotFound)
        }
    }

    // MARK: - Filtro

    func test_filtroPorProjeto() throws {
        let project = try sut.addProject(ProjectDraft(title: "Site"))
        let a = try tasks.addTask(title: "A", projectID: project.id)
        let b = try tasks.addTask(title: "B")
        let all = taskRepo.tasks
        XCTAssertEqual(TaskFilter(project: .project(project.id)).apply(all, now: now, calendar: calendar).map(\.id), [a.id])
        XCTAssertEqual(TaskFilter(project: .none).apply(all, now: now, calendar: calendar).map(\.id), [b.id])
        XCTAssertEqual(TaskFilter().apply(all, now: now, calendar: calendar).count, 2)
    }
}
