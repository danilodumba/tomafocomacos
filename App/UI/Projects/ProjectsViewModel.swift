import Combine
import Foundation
import TomafocoDomain
import TomafocoApplication

/// Cadastro de projetos (FEAT-006): lista + formulário no mesmo sheet, e os documentos do projeto
/// selecionado (FEAT-009). Aberto pela janela
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
    /// Código do projeto (RF-09.22, até 5 caracteres) e próximo número de tarefa.
    @Published var code = "" {
        didSet {
            // Limite na digitação (o use case valida de novo): mais de 5 nunca chega a salvar.
            let limited = String(code.uppercased().prefix(Project.maxCodeLength))
            if limited != code { code = limited }
        }
    }
    @Published var nextCodeNumber = 1

    @Published var feedback: String?
    /// Confirmação de apagar: projeto + quantas tarefas perdem o vínculo + quantos documentos saem.
    @Published var pendingDeletion: (project: Project, taskCount: Int, documentCount: Int)?

    // MARK: Documentos (FEAT-009)
    @Published private(set) var documents: [ProjectDocumentSummary] = []
    @Published var newDocumentTitle = ""
    @Published var pendingDocumentDeletion: ProjectDocumentSummary?

    private let useCase: ManageProjectsUseCase
    private let documentsUseCase: ManageProjectDocumentsUseCase
    /// Cancelada sozinha quando o VM (o sheet) morre.
    private var documentsObserver: AnyCancellable?
    /// Algo foi gravado — as janelas recarregam (cor/nome mudam nas linhas e cartões).
    private let onChanged: () -> Void
    /// "Ver tarefas": fecha o sheet e filtra a janela pelo projeto.
    private let onShowTasks: (UUID) -> Void
    private let onClose: () -> Void

    init(useCase: ManageProjectsUseCase, documents: ManageProjectDocumentsUseCase, onChanged: @escaping () -> Void,
         onShowTasks: @escaping (UUID) -> Void, onClose: @escaping () -> Void) {
        self.useCase = useCase
        self.documentsUseCase = documents
        self.onChanged = onChanged
        self.onShowTasks = onShowTasks
        self.onClose = onClose
        reload()
        if let first = projects.first { select(first) }
        // Documento renomeado/salvo na janela dele: a lista relê.
        documentsObserver = NotificationCenter.default.publisher(for: ProjectDocumentsChange.notification)
            .receive(on: DispatchQueue.main)
            // Main garantida pelo `receive(on:)`.
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.reloadDocuments() } }
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
        code = project.code ?? ""
        nextCodeNumber = project.nextCodeNumber
        newDocumentTitle = ""
        reloadDocuments()
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
        code = ""
        nextCodeNumber = 1
        documents = []
    }

    func save() {
        feedback = nil
        let draft = ProjectDraft(title: title, dueDate: hasDueDate ? dueDate : nil, color: color,
                                 icon: icon, details: details,
                                 code: code, nextCodeNumber: nextCodeNumber)
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
        } catch DomainError.invalidProjectCode(let maxLength) {
            feedback = "O código tem até \(maxLength) caracteres, sem espaços."
        } catch DomainError.duplicateProjectCode(let code) {
            feedback = "Outro projeto já usa o código \"\(code)\"."
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
            pendingDeletion = (project, try useCase.taskCount(of: project.id), try useCase.documentCount(of: project.id))
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

    // MARK: - Documentos (FEAT-009)

    func reloadDocuments() {
        guard let selectedID else {
            documents = []
            return
        }
        do {
            documents = try documentsUseCase.documents(projectID: selectedID)
        } catch {
            feedback = "Não foi possível ler os documentos: \(error.localizedDescription)"
        }
    }

    /// Cria um documento vazio no projeto selecionado e devolve o id — a View abre a janela dele.
    /// Título em branco vira "Sem título" (renomeia-se na própria janela).
    func createDocument() -> UUID? {
        feedback = nil
        guard let selectedID else { return nil }
        do {
            let document = try documentsUseCase.create(projectID: selectedID, title: newDocumentTitle)
            newDocumentTitle = ""
            reloadDocuments()
            return document.id
        } catch DomainError.projectNotFound {
            feedback = "Este projeto foi apagado em outra janela."
            reload()
        } catch {
            feedback = "Não foi possível criar o documento: \(error.localizedDescription)"
        }
        return nil
    }

    func confirmDocumentDeletion() {
        guard let pending = pendingDocumentDeletion else { return }
        pendingDocumentDeletion = nil
        do {
            try documentsUseCase.delete(id: pending.id)
            reloadDocuments()
            // Janela aberta deste documento passa a só leitura.
            onChanged()
            feedback = "Documento \"\(pending.title)\" apagado."
        } catch {
            feedback = "Não foi possível apagar o documento: \(error.localizedDescription)"
        }
    }

    func showTasks() {
        guard let selectedID else { return }
        onShowTasks(selectedID)
    }

    func close() { onClose() }
}
