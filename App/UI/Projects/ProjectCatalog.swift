import Foundation
import TomafocoDomain
import TomafocoApplication

/// Projetos carregados para uma tela (FEAT-006): lista ordenada (seletores/filtro) + índice por
/// id (linha e cartão consultam O(1)). Compartilhado pela lista e pelo Kanban.
struct ProjectCatalog {
    private(set) var all: [Project] = []
    private(set) var byID: [UUID: Project] = [:]

    /// Falha de leitura **mantém** o catálogo anterior: zerar aqui apagaria chips/faixas da tela
    /// e `validated` resetaria o filtro do usuário por um erro passageiro.
    @MainActor
    mutating func reload(from useCase: ManageProjectsUseCase) {
        guard let loaded = try? useCase.allProjects() else { return }
        all = loaded
        byID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
    }

    func project(of task: FocusTask) -> Project? {
        task.projectID.flatMap { byID[$0] }
    }

    /// Projeto do filtro, se for um projeto específico que ainda existe.
    func project(filteredBy filter: ProjectFilter) -> Project? {
        filter.projectIDForNewTask.flatMap { byID[$0] }
    }

    /// Filtro por projeto apagado (aqui ou em outra janela) volta a "Todos".
    func validated(_ filter: ProjectFilter) -> ProjectFilter {
        if case .project(let id) = filter, byID[id] == nil { return .all }
        return filter
    }
}

/// Tela que mostra projetos e abre o cadastro (janela Tarefas e Kanban).
@MainActor
protocol ProjectsHosting: AnyObject {
    var projectCatalog: ProjectCatalog { get set }
    var projectFilter: ProjectFilter { get set }
    var projectsSheet: ProjectsViewModel? { get set }
    var feedback: String? { get set }
    var manageProjects: ManageProjectsUseCase { get }
    /// Relê e avisa as outras janelas.
    func reload()
}

extension ProjectsHosting {
    var projects: [Project] { projectCatalog.all }

    /// Relê os projetos e desfaz o filtro por projeto apagado — chamado no `refresh()` das telas.
    func reloadProjects() {
        projectCatalog.reload(from: manageProjects)
        let validFilter = projectCatalog.validated(projectFilter)
        if validFilter != projectFilter { projectFilter = validFilter }
    }

    func project(of task: FocusTask) -> Project? { projectCatalog.project(of: task) }

    /// Projeto em que a tarefa criada nesta tela vai nascer (o filtrado), se houver.
    var newTaskProject: Project? { projectCatalog.project(filteredBy: projectFilter) }

    /// "Ver tarefas" fecha o sheet e filtra esta tela pelo projeto — é assim que se cria
    /// tarefa "dentro" de um projeto.
    func openProjects() {
        feedback = nil
        projectsSheet = ProjectsViewModel(
            useCase: manageProjects,
            onChanged: { [weak self] in self?.reload() },
            onShowTasks: { [weak self] id in
                self?.projectFilter = .project(id)
                self?.projectsSheet = nil
            },
            onClose: { [weak self] in self?.projectsSheet = nil })
    }
}
