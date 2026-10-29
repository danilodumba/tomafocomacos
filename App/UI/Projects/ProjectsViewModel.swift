import Foundation
import TomafocoDomain
import TomafocoApplication

/// Cadastro de projetos (FEAT-006): lista + formulário no mesmo sheet. Aberto pela janela
/// Tarefas ou pelo Kanban — cada abertura cria um VM, observado direto pelo `ProjectsSheet`.
@MainActor
final class ProjectsViewModel: ObservableObject, Identifiable {

    @Published private(set) var projects: [Project] = []
    /// Tarefas abertas por projeto (coluna da lista).
    @Published private(set) var openCounts: [UUID: Int] = [:]
    /// Projeto em edição; `nil` = formulário de projeto novo.
    @Published private(set) var selectedID: UUID?

    // Rascunho — só `save()` grava.
    @Published var title = ""
    @Published var hasDueDate = false
    @Published var dueDate = Date()
    @Published var color: ProjectColor = .cyan
    @Published var icon = Project.defaultIcon
    @Published var details = ""

    @Published var feedback: String?
    /// Confirmação de apagar: projeto + quantas tarefas perdem o vínculo.
    @Published var pendingDeletion: (project: Project, taskCount: Int)?

    private let useCase: ManageProjectsUseCase
    /// Algo foi gravado — as janelas recarregam (cor/nome mudam nas linhas e cartões).
    private let onChanged: () -> Void
    /// "Ver tarefas": fecha o sheet e filtra a janela pelo projeto.
    private let onShowTasks: (UUID) -> Void
    private let onClose: () -> Void

    init(useCase: ManageProjectsUseCase, onChanged: @escaping () -> Void,
         onShowTasks: @escaping (UUID) -> Void, onClose: @escaping () -> Void) {
        self.useCase = useCase
        self.onChanged = onChanged
        self.onShowTasks = onShowTasks
        self.onClose = onClose
        reload()
        if let first = projects.first { select(first) }
    }

    var selected: Project? { selectedID.flatMap { id in projects.first { $0.id == id } } }

    var createdAtText: String? {
        selected?.createdAt.formatted(date: .abbreviated, time: .shortened)
    }

    func isOverdue(_ project: Project) -> Bool {
        project.isOverdue(now: Date(), calendar: .current)
    }

    func reload() {
        do {
            projects = try useCase.allProjects()
            openCounts = try useCase.openTaskCounts()
        } catch {
            feedback = "Não foi possível ler os projetos: \(error.localizedDescription)"
        }
        if let selectedID, !projects.contains(where: { $0.id == selectedID }) { newProject() }
    }

    func select(_ project: Project) {
        feedback = nil
        selectedID = project.id
        title = project.title
        hasDueDate = project.dueDate != nil
        dueDate = project.dueDate ?? Date()
        color = project.color
        icon = project.icon
        details = project.details ?? ""
    }

    func newProject() {
        feedback = nil
        selectedID = nil
        title = ""
        hasDueDate = false
        dueDate = Date()
        color = .cyan
        icon = Project.defaultIcon
        details = ""
    }

    func save() {
        feedback = nil
        let draft = ProjectDraft(title: title, dueDate: hasDueDate ? dueDate : nil, color: color,
                                 icon: icon, details: details)
        do {
            let saved = if let selectedID {
                try useCase.editProject(id: selectedID, draft)
            } else {
                try useCase.addProject(draft)
            }
            reload()
            select(saved)
            onChanged()
            feedback = "Projeto salvo."
        } catch DomainError.emptyProjectTitle {
            feedback = "Informe um título para o projeto."
        } catch DomainError.duplicateProject(let title) {
            feedback = "Já existe um projeto chamado \"\(title)\"."
        } catch DomainError.projectNotFound {
            feedback = "Este projeto foi apagado em outra janela."
            reload()
        } catch {
            feedback = "Não foi possível salvar: \(error.localizedDescription)"
        }
    }

    func requestDeletion() {
        guard let project = selected else { return }
        do {
            pendingDeletion = (project, try useCase.taskCount(of: project.id))
        } catch {
            feedback = "Não foi possível apagar: \(error.localizedDescription)"
        }
    }

    func confirmDeletion() {
        guard let pending = pendingDeletion else { return }
        pendingDeletion = nil
        do {
            try useCase.deleteProject(id: pending.project.id)
            reload() // o selecionado sumiu → `reload` já volta ao formulário de novo projeto
            onChanged()
            feedback = "Projeto \"\(pending.project.title)\" apagado."
        } catch {
            feedback = "Não foi possível apagar: \(error.localizedDescription)"
        }
    }

    func showTasks() {
        guard let selectedID else { return }
        onShowTasks(selectedID)
    }

    func close() { onClose() }
}
