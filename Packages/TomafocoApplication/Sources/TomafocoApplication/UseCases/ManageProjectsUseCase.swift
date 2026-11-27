import Foundation
import TomafocoDomain

/// Rascunho do formulário de projeto (FEAT-006). Valores crus — quem normaliza é o use case.
public struct ProjectDraft: Equatable, Sendable {
    public var title: String
    public var dueDate: Date?
    public var color: ProjectColor
    public var icon: String
    public var details: String?
    /// Código do projeto (RF-09.22) — cru; o use case faz trim/maiúsculas e valida.
    public var code: String?
    /// Próximo número de tarefa ("número inicial" no cadastro novo).
    public var nextCodeNumber: Int

    public init(title: String, dueDate: Date? = nil, color: ProjectColor = .cyan,
                icon: String = Project.defaultIcon, details: String? = nil,
                code: String? = nil, nextCodeNumber: Int = 1) {
        self.title = title
        self.dueDate = dueDate
        self.color = color
        self.icon = icon
        self.details = details
        self.code = code
        self.nextCodeNumber = nextCodeNumber
    }
}

/// Cadastro de projetos (FEAT-006 / RF-09.16).
@MainActor
public final class ManageProjectsUseCase {
    private let projects: ProjectRepository
    private let tasks: TaskRepository
    private let unitOfWork: UnitOfWork
    private let now: () -> Date
    private let makeID: () -> UUID
    private let calendar: Calendar
    /// Quadros Kanban (FEAT-008): apagar um projeto tira ele do escopo dos quadros.
    private let kanbanBoards: KanbanBoardRepository?
    /// Documentos do projeto (FEAT-009): saem junto com o projeto.
    private let projectDocuments: ProjectDocumentRepository?

    // `now` sem default: `Date()` é proibido na Application.
    public init(projects: ProjectRepository, tasks: TaskRepository, unitOfWork: UnitOfWork,
                now: @escaping () -> Date, makeID: @escaping () -> UUID = { UUID() },
                calendar: Calendar = .current, kanbanBoards: KanbanBoardRepository? = nil,
                projectDocuments: ProjectDocumentRepository? = nil) {
        self.projects = projects
        self.tasks = tasks
        self.unitOfWork = unitOfWork
        self.now = now
        self.makeID = makeID
        self.calendar = calendar
        self.kanbanBoards = kanbanBoards
        self.projectDocuments = projectDocuments
    }

    /// Ordenados por título (ordem "natural" do Finder).
    public func allProjects() throws -> [Project] {
        try projects.loadProjects().sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    /// Lança `emptyProjectTitle`, `duplicateProject`, `invalidProjectCode` ou `duplicateProjectCode`.
    @discardableResult
    public func addProject(_ draft: ProjectDraft) throws -> Project {
        let all = try projects.loadProjects()
        let title = try validatedTitle(draft.title, excluding: nil, in: all)
        let code = try validatedCode(draft.code, excluding: nil, in: all)
        let project = Project(
            id: makeID(), title: title, createdAt: now(), dueDate: normalizedDueDate(draft.dueDate),
            color: draft.color, icon: draft.icon, details: FocusTask.normalizeNotes(draft.details),
            code: code, nextCodeNumber: draft.nextCodeNumber)
        try projects.upsert(project)
        return project
    }

    /// Duplicata exclui o próprio projeto (salvar sem mexer no título não acusa). Inexistente →
    /// `projectNotFound`. `createdAt` nunca muda.
    @discardableResult
    public func editProject(id: UUID, _ draft: ProjectDraft) throws -> Project {
        let all = try projects.loadProjects()
        guard var project = all.first(where: { $0.id == id }) else { throw DomainError.projectNotFound }
        project.title = try validatedTitle(draft.title, excluding: id, in: all)
        project.dueDate = normalizedDueDate(draft.dueDate)
        project.color = draft.color
        project.icon = draft.icon
        project.details = FocusTask.normalizeNotes(draft.details)
        // Código (RF-09.22): mudar o prefixo não renomeia os códigos já dados às tarefas.
        project.code = try validatedCode(draft.code, excluding: id, in: all)
        project.nextCodeNumber = max(draft.nextCodeNumber, 1)
        try projects.upsert(project)
        return project
    }

    /// Apaga o projeto e tira o vínculo de **todas** as tarefas dele (abertas e concluídas) numa
    /// transação só. Não apaga tarefa nenhuma. Devolve quantas tarefas ficaram sem projeto.
    /// Quadro Kanban com escopo neste projeto volta a "todos os projetos" (FEAT-008, decisão P4)
    /// na mesma transação. Os documentos do projeto (FEAT-009) são apagados, também na transação.
    @discardableResult
    public func deleteProject(id: UUID) throws -> Int {
        try unitOfWork.perform {
            var all = try tasks.loadTasks()
            var affected = 0
            for idx in all.indices where all[idx].projectID == id {
                all[idx].projectID = nil
                affected += 1
            }
            if affected > 0 { try tasks.saveTasks(all) }
            if let kanbanBoards {
                var boards = try kanbanBoards.loadBoards()
                var changed = false
                for idx in boards.indices where boards[idx].projectScope == .project(id) {
                    boards[idx].projectScope = .all
                    changed = true
                }
                if changed { try kanbanBoards.saveBoards(boards) }
            }
            try projectDocuments?.delete(projectID: id)
            try projects.delete(id: id)
            return affected
        }
    }

    /// Quantos documentos o projeto tem — a confirmação de apagar avisa que eles vão junto.
    public func documentCount(of id: UUID) throws -> Int {
        try projectDocuments?.summaries(projectID: id).count ?? 0
    }

    /// Tarefas abertas por projeto — contagem da lista de projetos e da confirmação de apagar.
    public func openTaskCounts() throws -> [UUID: Int] {
        var counts: [UUID: Int] = [:]
        for task in try tasks.loadTasks() where !task.isCompleted {
            if let projectID = task.projectID { counts[projectID, default: 0] += 1 }
        }
        return counts
    }

    /// Todas as tarefas do projeto (abertas e concluídas) — o que perde o vínculo ao apagar.
    public func taskCount(of id: UUID) throws -> Int {
        try tasks.loadTasks().filter { $0.projectID == id }.count
    }

    // MARK: - Privado

    private func validatedTitle(_ raw: String, excluding id: UUID?, in all: [Project]) throws -> String {
        let title = Project.normalizeTitle(raw)
        guard !title.isEmpty else { throw DomainError.emptyProjectTitle }
        let clash = all.contains {
            $0.id != id && $0.title.compare(title, options: [.caseInsensitive]) == .orderedSame
        }
        guard !clash else { throw DomainError.duplicateProject(title) }
        return title
    }

    /// Código limpo e único entre os projetos (sem distinção de caixa) — dois projetos com o mesmo
    /// prefixo dariam o mesmo código a tarefas diferentes.
    private func validatedCode(_ raw: String?, excluding id: UUID?, in all: [Project]) throws -> String? {
        guard let code = try Project.normalizeCode(raw) else { return nil }
        let clash = all.contains {
            $0.id != id && $0.code?.compare(code, options: [.caseInsensitive]) == .orderedSame
        }
        guard !clash else { throw DomainError.duplicateProjectCode(code) }
        return code
    }

    /// Prazo é um dia: guarda o início do dia (hora descartada).
    private func normalizedDueDate(_ date: Date?) -> Date? {
        date.map { calendar.startOfDay(for: $0) }
    }
}
