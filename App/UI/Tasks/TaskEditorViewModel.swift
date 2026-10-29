import Foundation
import TomafocoDomain
import TomafocoApplication

/// Formulário de edição de uma tarefa (RF-09.6) + histórico (FEAT-001) + subtarefas (FEAT-003).
/// Compartilhado entre a janela Tarefas e o Kanban (FEAT-005): cada edição cria um editor,
/// apresentado com `.sheet(item:)` e observado direto pelo `TaskEditorSheet`.
///
/// Os campos são rascunho — só `save()` grava. Histórico e subtarefas **não** são rascunho:
/// gravam na hora, e "Cancelar" não desfaz entrada/subtarefa já adicionada.
@MainActor
final class TaskEditorViewModel: ObservableObject, Identifiable {
    let task: FocusTask
    let knownTags: [String]
    /// Pai quando a tarefa editada é uma subtarefa (FEAT-003) — título no cabeçalho, que é um
    /// botão para abrir o editor do pai (`openParent`).
    let parent: FocusTask?
    var parentTitle: String? { parent?.title }

    @Published var title: String
    /// Tags do rascunho, separadas por vírgula (mesmo formato do campo de criação).
    @Published var tags: String
    /// Vencimento é opcional: o toggle liga/desliga o `DatePicker` e desligado grava `nil`.
    @Published var hasDueDate: Bool
    @Published var dueDate: Date
    @Published var priority: TaskPriority
    /// "Repetir diariamente" (FEAT-004).
    @Published var repeatsDaily: Bool
    /// Nota, link e urgente (RF-09.13). Link cru — o use case completa `https://` e valida.
    @Published var notes: String
    @Published var link: String
    @Published var isUrgent: Bool
    /// Projeto (FEAT-006). Em subtarefa é só exibição — vale o do pai (`isProjectInherited`).
    @Published var projectID: UUID?
    /// Snapshot de quando o sheet abriu; projeto que o use case recusou (apagado) sai daqui.
    @Published private(set) var projects: [Project]
    /// "Agora" da tela que abriu o editor (FEAT-006, H3) — o destaque de atrasada nas subtarefas
    /// usa o mesmo relógio da lista/quadro atrás do sheet.
    let now: () -> Date
    /// Erro do formulário — separado do feedback da janela porque o sheet cobre a tela.
    @Published var feedback: String?
    /// Histórico da tarefa, mais recente primeiro.
    @Published private(set) var history: [TaskHistoryEntry]
    /// Texto da entrada de histórico em digitação.
    @Published var newHistoryText = ""
    /// Subtarefas (FEAT-003): tarefas completas com `parentID == task.id`, abertas primeiro na
    /// ordem de criação, concluídas depois. Espelho atualizado a cada gravação.
    @Published private(set) var subtasks: [FocusTask]
    /// Título da subtarefa em digitação.
    @Published var newSubtaskTitle = ""
    /// Subtarefa com concluir/reabrir em andamento (o círculo vira loading).
    @Published private(set) var busySubtaskIDs: Set<UUID> = []

    private let useCase: ManageTasksUseCase
    /// Algo foi gravado (rascunho salvo, histórico ou subtarefa) — a janela recarrega.
    private let onChanged: () -> Void
    /// Fechar o sheet (salvou ou cancelou).
    private let onClose: () -> Void
    /// Abrir o formulário de OUTRA tarefa (a subtarefa clicada) — a janela troca o editor.
    private let onOpenTask: (FocusTask) -> Void

    init(task: FocusTask, knownTags: [String], projects: [Project], now: @escaping () -> Date = { Date() },
         useCase: ManageTasksUseCase, onChanged: @escaping () -> Void, onClose: @escaping () -> Void,
         onOpenTask: @escaping (FocusTask) -> Void = { _ in }) {
        self.task = task
        self.knownTags = knownTags
        self.projects = projects
        self.now = now
        self.useCase = useCase
        self.onChanged = onChanged
        self.onClose = onClose
        self.onOpenTask = onOpenTask
        title = task.title
        tags = task.tags.joined(separator: ", ")
        hasDueDate = task.dueDate != nil
        dueDate = task.dueDate ?? Self.defaultDueDate()
        priority = TaskPriority(rawPriority: task.priority)
        repeatsDaily = task.repeatsDaily
        notes = task.notes ?? ""
        link = task.sourceURL ?? ""
        isUrgent = task.isUrgent
        projectID = task.projectID
        history = Self.sortedHistory(task)
        let all = (try? useCase.allTasks()) ?? []
        subtasks = Self.sortedChildren(of: task, in: all)
        parent = TaskTree.parent(of: task, in: all)
    }

    /// Subtarefa tem o projeto do pai (FEAT-006): o seletor só mostra, não edita.
    var isProjectInherited: Bool { task.isSubtask }

    /// Um nível só (FEAT-003): subtarefa não tem a seção de subtarefas.
    var canHaveSubtasks: Bool { !task.isSubtask }

    /// Datas só leitura do formulário: cadastro e encerramento. Vêm da tarefa como foi aberta
    /// (concluir/reabrir acontece fora do sheet); encerramento vazio = tarefa aberta.
    var createdAtText: String { Self.readOnlyDate(task.createdAt) }
    var completedAtText: String? { task.completedAt.map(Self.readOnlyDate) }

    private static func readOnlyDate(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    /// Progresso do checklist para o cabeçalho da seção (`2/5`).
    var subtaskProgress: (done: Int, total: Int) {
        (subtasks.filter(\.isCompleted).count, subtasks.count)
    }

    /// URL do link digitado, para o botão "Abrir" — `nil` enquanto não for um link válido.
    /// Link que veio gravado (ex.: `mailto:` do Lembretes) abre como está, sem renormalizar —
    /// mesma regra do use case.
    var linkURL: URL? {
        if link == task.sourceURL { return URL(string: link) }
        guard let normalized = try? FocusTask.normalizeLink(link) else { return nil }
        return URL(string: normalized)
    }

    func cancel() { onClose() }

    /// Grava o rascunho. Erro de validação mantém o sheet aberto com a mensagem.
    ///
    /// Três gravações em sequência (rascunho, entrada de histórico pendente, subtarefa pendente).
    /// Se uma falha depois de outra já ter gravado, as janelas ainda precisam recarregar
    /// (`onChanged` no `defer`) e a mensagem diz QUAL falhou — "título duplicado" para uma
    /// subtarefa repetida enganaria.
    func save() {
        feedback = nil
        var wroteSomething = false
        defer { if wroteSomething { onChanged() } }
        do {
            try useCase.editTask(id: task.id, TaskEdit(
                title: title,
                tags: Self.parseTags(tags),
                dueDate: hasDueDate ? dueDate : nil,
                priority: priority,
                repeatsDaily: repeatsDaily,
                notes: notes,
                link: link,
                isUrgent: isUrgent,
                projectID: projectID
            ))
            wroteSomething = true
        } catch DomainError.emptyTaskTitle {
            feedback = "Informe um título para a tarefa."
            return
        } catch DomainError.duplicateEntry(let title) {
            feedback = "Já existe uma tarefa ativa chamada \"\(title)\"."
            return
        } catch DomainError.invalidLink(let raw) {
            feedback = "\"\(raw)\" não é um link válido. Use algo como site.com ou https://site.com/pagina."
            return
        } catch DomainError.projectNotFound {
            feedback = "O projeto escolhido foi apagado. Escolha outro ou \"Sem projeto\"."
            if let missing = projectID { projects.removeAll { $0.id == missing } }
            projectID = nil
            return
        } catch {
            feedback = "Não foi possível salvar: \(error.localizedDescription)"
            return
        }

        // Texto digitado no histórico sem clicar "Adicionar" entra junto ao salvar — não
        // descartar em silêncio o que o usuário escreveu. Mesma regra para a subtarefa.
        if !newHistoryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            do {
                if let updated = try useCase.addHistoryEntry(taskID: task.id, text: newHistoryText) {
                    history = Self.sortedHistory(updated)
                }
                newHistoryText = ""
            } catch {
                feedback = "Rascunho salvo, mas não foi possível gravar a entrada do histórico: \(error.localizedDescription)"
                return
            }
        }
        if !newSubtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            do {
                try useCase.addSubtask(parentID: task.id, title: newSubtaskTitle)
                newSubtaskTitle = ""
            } catch DomainError.duplicateEntry(let title) {
                feedback = "Rascunho salvo. Já existe uma subtarefa ativa chamada \"\(title)\" nesta tarefa."
                refreshSubtasks()
                return
            } catch {
                feedback = "Rascunho salvo, mas não foi possível criar a subtarefa: \(error.localizedDescription)"
                return
            }
        }
        onClose()
    }

    // MARK: - Histórico (FEAT-001)

    /// Acrescenta a entrada digitada. **Grava na hora**, fora do rascunho do formulário.
    func addHistoryEntry() {
        feedback = nil
        do {
            guard let updated = try useCase.addHistoryEntry(taskID: task.id, text: newHistoryText) else { return }
            history = Self.sortedHistory(updated)
            newHistoryText = ""
            onChanged()
        } catch DomainError.emptyHistoryEntry {
            feedback = "Escreva algo antes de adicionar ao histórico."
        } catch {
            feedback = "Não foi possível salvar a entrada: \(error.localizedDescription)"
        }
    }

    /// Apaga UMA entrada (não há edição — é log).
    func deleteHistoryEntry(_ entry: TaskHistoryEntry) {
        feedback = nil
        do {
            guard let updated = try useCase.deleteHistoryEntry(taskID: task.id, entryID: entry.id) else { return }
            history = Self.sortedHistory(updated)
            onChanged()
        } catch {
            feedback = "Não foi possível apagar a entrada: \(error.localizedDescription)"
        }
    }

    // MARK: - Subtarefas (FEAT-003)

    /// Cria a subtarefa digitada (só título; o resto se edita abrindo a subtarefa). **Grava na hora.**
    func addSubtask() {
        feedback = nil
        do {
            try useCase.addSubtask(parentID: task.id, title: newSubtaskTitle)
            newSubtaskTitle = ""
            refreshSubtasks()
            onChanged()
        } catch DomainError.emptyTaskTitle {
            feedback = "Escreva o título da subtarefa antes de adicionar."
        } catch DomainError.duplicateEntry(let title) {
            feedback = "Já existe uma subtarefa ativa chamada \"\(title)\" nesta tarefa."
        } catch {
            feedback = "Não foi possível criar a subtarefa: \(error.localizedDescription)"
        }
    }

    /// Conclui/reabre a subtarefa pelo círculo — mesma regra da lista (sync Lembretes, diária).
    /// Não mexe no pai: fechar todas não conclui a tarefa.
    func toggleSubtask(_ subtask: FocusTask) {
        guard !busySubtaskIDs.contains(subtask.id) else { return }
        feedback = nil
        busySubtaskIDs.insert(subtask.id)
        Task {
            defer { busySubtaskIDs.remove(subtask.id) }
            do {
                if subtask.isCompleted {
                    try await useCase.reopenTask(id: subtask.id)
                } else {
                    try await useCase.completeTask(id: subtask.id)
                }
                refreshSubtasks()
                onChanged()
            } catch {
                feedback = "Não foi possível atualizar a subtarefa: \(error.localizedDescription)"
            }
        }
    }

    /// Apaga a subtarefa (ela não tem filhas — um nível só — então sem confirmação).
    func deleteSubtask(_ subtask: FocusTask) {
        feedback = nil
        do {
            try useCase.deleteTask(id: subtask.id)
            refreshSubtasks()
            onChanged()
        } catch {
            feedback = "Não foi possível apagar a subtarefa: \(error.localizedDescription)"
        }
    }

    /// Edição completa da subtarefa (tags, prioridade, vencimento…): troca este editor pelo dela.
    func openSubtask(_ subtask: FocusTask) {
        onOpenTask(subtask)
    }

    /// Caminho inverso: do editor da subtarefa para o do pai (clique no "↳ Pai" do cabeçalho).
    /// Mesma troca de editor que `openSubtask` — o rascunho desta não é gravado.
    func openParent() {
        guard let parent else { return }
        onOpenTask(parent)
    }

    private func refreshSubtasks() {
        let all = (try? useCase.allTasks()) ?? []
        subtasks = Self.sortedChildren(of: task, in: all)
    }

    /// Abertas na ordem de criação (é um checklist), concluídas no fim (mais recente primeiro).
    private static func sortedChildren(of task: FocusTask, in all: [FocusTask]) -> [FocusTask] {
        let kids = TaskTree.children(of: task.id, in: all)
        return kids.filter { !$0.isCompleted }.sorted { $0.createdAt < $1.createdAt }
            + kids.filter(\.isCompleted).sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }

    /// Ordem de exibição: mais recente primeiro (o Domain guarda na ordem de inclusão).
    private static func sortedHistory(_ task: FocusTask) -> [TaskHistoryEntry] {
        task.history.sorted { $0.createdAt > $1.createdAt }
    }

    /// Sugestão ao ligar o vencimento numa tarefa que não tinha: hoje na próxima hora cheia
    /// (data crua com segundos do "agora" viraria um horário estranho no picker).
    static func defaultDueDate() -> Date {
        let calendar = Calendar.current
        let next = calendar.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
        var parts = calendar.dateComponents([.year, .month, .day, .hour], from: next)
        parts.minute = 0
        parts.second = 0
        return calendar.date(from: parts) ?? next
    }

    /// Divide o texto do campo em tags cruas (por vírgula) — a normalização final é do Domain.
    static func parseTags(_ text: String) -> [String] {
        text.split(separator: ",").map(String.init)
    }
}
