import Foundation
import SwiftUI
import TomafocoDomain
import TomafocoApplication

/// ViewModel da aba Tarefas (RF-09): CRUD manual + importação do Lembretes.
@MainActor
final class TasksViewModel: ObservableObject, TaskRowActionRunning, ProjectsHosting, MinuteClockHosting {

    @Published private(set) var activeTasks: [FocusTask] = []
    @Published private(set) var completedTasks: [FocusTask] = []
    /// Todas as tags conhecidas (uso + catálogo) — alimenta autocomplete, filtro e o gestor.
    @Published private(set) var knownTags: [String] = []
    @Published var newTitle = ""
    /// Tags da nova tarefa, digitadas separadas por vírgula.
    @Published var newTags = ""
    /// Formulário de edição aberto (RF-09.6) — `nil` = fechado. Compartilhado com o Kanban.
    @Published var editor: TaskEditorViewModel?

    // Ordenação + filtros da lista de ativas (itens 5 e 7).
    /// Persistida: a última ordenação escolhida volta na próxima abertura da janela/app.
    /// Filtros e busca NÃO são persistidos de propósito — recorte é da sessão; ordenação e
    /// exibição de concluídas são preferência.
    @Published var sortOrder: TaskSortOrder = .createdAt {
        didSet { defaults.set(sortOrder.rawValue, forKey: Self.sortOrderKey) }
    }
    /// Persistida: mostrar/ocultar concluídas é preferência de exibição, como a ordenação.
    /// Chave ausente → `false` (concluídas escondidas, comportamento antigo).
    @Published var showsCompleted: Bool = false {
        didSet { defaults.set(showsCompleted, forKey: Self.showsCompletedKey) }
    }
    @Published var searchText = ""
    @Published var tagFilter: String?
    @Published var priorityFilter: TaskPriority?
    /// Recorte por vencimento (FEAT-005): hoje / próximos 7 dias / atrasadas.
    @Published var dueFilter: TaskDueFilter = .all
    /// Recorte por projeto (FEAT-006). Com um projeto filtrado, a tarefa criada aqui nasce nele.
    @Published var projectFilter: ProjectFilter = .all
    /// Projetos da tela (FEAT-006) — ver `ProjectsHosting`.
    @Published var projectCatalog = ProjectCatalog()
    /// Sheet de cadastro de projetos (FEAT-006) — `nil` = fechado.
    @Published var projectsSheet: ProjectsViewModel?
    /// Tarefas com concluir/reabrir/apagar em andamento — a linha mostra loading no lugar do botão
    /// (trava em `TaskRowActionRunning`).
    @Published var busyTaskIDs: Set<UUID> = []
    /// "Agora" da tela (FEAT-006, H3): filtro por vencimento e destaque de atrasada leem daqui.
    /// Avança a cada minuto enquanto a janela está aberta (`didAppear`).
    @Published var now = Date()
    let clock = MinuteClock()

    /// Sheet de criação em lote (RF-09.8) — `nil` = fechado.
    @Published var bulkAdd: BulkAddTasksViewModel?
    /// Abre a tela de gestão de tags (item 1).
    @Published var showsTagManager = false
    /// Mensagem de resultado/erro exibida sob a toolbar (some na próxima ação).
    @Published var feedback: String?
    /// Linhas com o checklist aberto (FEAT-003). Só memória — recorte de sessão, não preferência.
    @Published var expandedTaskIDs: Set<UUID> = []
    /// Acesso ao Lembretes negado — a UI mostra o atalho para os Ajustes de Privacidade.
    @Published private(set) var accessDenied = false
    @Published private(set) var isImporting = false

    /// Sheet de escolha individual dos lembretes a importar (RF-09.3).
    @Published var showsImportSheet = false
    /// Lembretes não concluídos disponíveis para escolha (todas as listas).
    @Published private(set) var availableReminders: [ImportedReminder] = []
    /// Texto de busca por título dentro do sheet.
    @Published var reminderSearch = ""
    /// `reminderID`s com tarefa **ativa** — só essas linhas ficam marcadas/desabilitadas.
    @Published private(set) var importedReminderIDs: Set<String> = []
    /// `reminderID`s cuja tarefa já foi concluída aqui. Continuam importáveis (lembrete
    /// recorrente: concluir a ocorrência de hoje não pode barrar a de amanhã) — a linha só
    /// avisa que é uma reimportação.
    @Published private(set) var reimportableReminderIDs: Set<String> = []

    /// Lembretes filtrados pela busca por título (case-insensitive).
    var filteredReminders: [ImportedReminder] {
        let query = reminderSearch.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return availableReminders }
        return availableReminders.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }

    private let defaults: UserDefaults
    /// Chave da ordenação salva. Valor inválido/ausente cai em `.createdAt`.
    private static let sortOrderKey = "tasksSortOrder"
    private static let showsCompletedKey = "tasksShowsCompleted"

    private let useCase: ManageTasksUseCase
    let manageProjects: ManageProjectsUseCase
    /// Avisa que as tarefas mudaram por aqui — o seletor do timer e o Kanban recarregam.
    private let onTasksChanged: () -> Void

    init(useCase: ManageTasksUseCase, manageProjects: ManageProjectsUseCase,
         defaults: UserDefaults = .standard, onTasksChanged: @escaping () -> Void) {
        self.useCase = useCase
        self.manageProjects = manageProjects
        self.defaults = defaults
        self.onTasksChanged = onTasksChanged
        sortOrder = TaskSortOrder.stored(in: defaults, key: Self.sortOrderKey)
        showsCompleted = defaults.bool(forKey: Self.showsCompletedKey)
        refresh()
    }

    /// Relê e avisa as outras telas (timer, Kanban) — usado depois de toda mudança feita aqui.
    func reload() {
        refresh()
        onTasksChanged()
    }

    /// Só relê. É o que as outras janelas chamam quando a mudança veio delas — chamar `reload()`
    /// ali avisaria de volta e as janelas ficariam se avisando em laço.
    /// Janela abriu: relê, avisa e liga o relógio de minuto.
    func didAppear() {
        reload()
        startMinuteClock()
    }

    func didDisappear() {
        stopMinuteClock()
    }

    func refresh() {
        resetNow()
        let all = (try? useCase.allTasks()) ?? []
        activeTasks = all.filter { !$0.isCompleted }
        completedTasks = all.filter(\.isCompleted).sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
        // Índice pai → filhas montado UMA vez por leitura: `displayedTasks`, `isExpanded` e o
        // badge consultam por linha a cada render — varrer `allTasks` em cada uma era O(n²).
        activeChildren = Dictionary(grouping: activeTasks.filter(\.isSubtask), by: { $0.parentID! })
        completedChildren = Dictionary(grouping: completedTasks.filter(\.isSubtask), by: { $0.parentID! })
        importedReminderIDs = Set(activeTasks.compactMap(\.reminderID))
        reimportableReminderIDs = Set(completedTasks.compactMap(\.reminderID))
            .subtracting(importedReminderIDs)
        knownTags = (try? useCase.allTags()) ?? []
        reloadProjects()
        // Tarefa apagada em outra janela fecha o formulário em vez de editar algo que não existe.
        if let editor, !(activeTasks + completedTasks).contains(where: { $0.id == editor.task.id }) {
            self.editor = nil
        }
    }

    /// Lista para exibição — só as tarefas **de topo** (FEAT-003: as subtarefas aparecem
    /// aninhadas, via `children(of:)`): ativas buscadas/filtradas/ordenadas (itens 5 e 7) e, com
    /// `showsCompleted`, as concluídas em bloco no fim — na ordem de conclusão do `reload()`,
    /// não na `sortOrder` (vencimento/prioridade/atraso não dizem nada de tarefa finalizada).
    var displayedTasks: [FocusTask] {
        var result = applyFilters(TaskTree.topLevel(activeTasks)).sorted(by: sortOrder.areInIncreasingOrder)
        if showsCompleted {
            result += applyFilters(TaskTree.topLevel(completedTasks)) // já vêm por completedAt desc do reload()
        }
        return result
    }

    private var filter: TaskFilter {
        TaskFilter(searchText: searchText, tag: tagFilter, priority: priorityFilter, due: dueFilter,
                   project: projectFilter)
    }

    /// Busca, tag, prioridade e vencimento — a tarefa de topo entra se ela OU alguma subtarefa
    /// casa (achar a tarefa pelo passo). Vale para ativas e concluídas.
    private func applyFilters(_ tasks: [FocusTask]) -> [FocusTask] {
        let filter = self.filter
        let now = self.now
        return tasks.filter {
            filter.matchesTree($0, children: allChildren(of: $0.id), now: now, calendar: .current)
        }
    }

    private var allTasks: [FocusTask] { activeTasks + completedTasks }

    /// Índices pai → filhas (FEAT-003), reconstruídos no `refresh()`. Só subtarefas entram.
    private var activeChildren: [UUID: [FocusTask]] = [:]
    private var completedChildren: [UUID: [FocusTask]] = [:]

    private func allChildren(of parentID: UUID) -> [FocusTask] {
        (activeChildren[parentID] ?? []) + (completedChildren[parentID] ?? [])
    }

    func addTask() {
        feedback = nil
        do {
            try useCase.addTask(title: newTitle, tags: TaskEditorViewModel.parseTags(newTags),
                                projectID: projectFilter.projectIDForNewTask)
            newTitle = ""
            newTags = ""
            reload()
        } catch DomainError.emptyTaskTitle {
            feedback = "Informe um título para a tarefa."
        } catch DomainError.duplicateEntry(let title) {
            feedback = "Já existe uma tarefa ativa chamada \"\(title)\"."
        } catch DomainError.projectNotFound {
            feedback = "O projeto filtrado foi apagado."
            refresh()
        } catch {
            feedback = "Não foi possível salvar: \(error.localizedDescription)"
        }
    }

    // MARK: - Criação em lote (RF-09.8)

    func beginBulkAdd() {
        feedback = nil
        bulkAdd = BulkAddTasksViewModel(
            useCase: useCase,
            knownTags: knownTags,
            projects: projects,
            defaultProjectID: projectFilter.projectIDForNewTask,
            onCreated: { [weak self] count in
                guard let self else { return }
                self.bulkAdd = nil
                self.reload()
                self.feedback = count == 1 ? "1 tarefa criada." : "\(count) tarefas criadas."
            },
            onCancel: { [weak self] in self?.bulkAdd = nil }
        )
    }

    func setCompleted(_ task: FocusTask, _ completed: Bool) {
        runRowAction(task.id) {
            let outcome = completed
                ? try await self.useCase.completeTask(id: task.id)
                : try await self.useCase.reopenTask(id: task.id)
            self.reload()
            // Diária (FEAT-004): a concluída sai e um clone entra — sem aviso, parece que o clique
            // não fez nada (ou que a tarefa "não concluiu").
            if completed && task.repeatsDaily {
                self.feedback = "\"\(task.title)\" concluída — nova cópia criada com vencimento amanhã."
            }
            // Falha de espelhamento não desfaz a mudança local, mas precisa aparecer:
            // sem aviso, o usuário só descobre abrindo o Lembretes.
            if outcome == .failed {
                self.feedback = "Tarefa atualizada aqui, mas não foi possível refletir no Lembretes"
                    + " (lembrete apagado ou acesso negado em Ajustes › Privacidade › Lembretes)."
            }
        } onError: { error in
            "Não foi possível atualizar: \(error.localizedDescription)"
        }
    }

    // MARK: - Subtarefas na lista (FEAT-003)

    func toggleExpanded(_ taskID: UUID) {
        if expandedTaskIDs.contains(taskID) {
            expandedTaskIDs.remove(taskID)
        } else {
            expandedTaskIDs.insert(taskID)
        }
    }

    /// Aberta pelo chevron ou, com filtro ativo, quando alguma subtarefa casa — senão a busca
    /// "acha" a tarefa pela subtarefa e o usuário não vê qual.
    func isExpanded(_ task: FocusTask) -> Bool {
        if expandedTaskIDs.contains(task.id) { return true }
        guard hasActiveFilters else { return false }
        let filter = self.filter
        return children(of: task).contains { filter.matches($0, now: now, calendar: .current) }
    }

    private var hasActiveFilters: Bool {
        !searchText.trimmingCharacters(in: .whitespaces).isEmpty
            || tagFilter != nil || priorityFilter != nil || dueFilter != .all || projectFilter != .all
    }

    /// Subtarefas da linha: abertas na `sortOrder`, concluídas no fim por data de conclusão.
    /// Sempre todas (sem recorte por filtro/`showsCompleted`): é o checklist do pai — o `2/5`
    /// só faz sentido vendo as feitas.
    func children(of task: FocusTask) -> [FocusTask] {
        (activeChildren[task.id] ?? []).sorted(by: sortOrder.areInIncreasingOrder)
            + (completedChildren[task.id] ?? []) // já vêm por completedAt desc do refresh()
    }

    func subtaskProgress(of task: FocusTask) -> (done: Int, total: Int) {
        let done = completedChildren[task.id]?.count ?? 0
        return (done, done + (activeChildren[task.id]?.count ?? 0))
    }

    /// Soltar uma linha sobre outra: a arrastada vira subtarefa da alvo. O payload é texto (o
    /// arraste pode vir de fora do app) — só UUID de tarefa existente conta. Soltar sobre si
    /// mesma ou durante uma ação de linha é recusado de cara. Devolve `false` quando a regra
    /// recusa (pai com filhas, alvo já é subtarefa…) para o arraste voltar; o motivo vai pro
    /// `feedback`.
    func handleDrop(_ items: [String], onto target: FocusTask) -> Bool {
        guard !isMutatingTask,
              let dragged = items.lazy.compactMap(UUID.init(uuidString:))
                  .compactMap({ id in self.allTasks.first { $0.id == id } }).first,
              dragged.id != target.id else { return false }
        return makeSubtask(dragged, of: target)
    }

    /// Alvos possíveis para "Tornar subtarefa de ▸" (alternativa acessível ao arraste): tarefas
    /// de topo ativas, menos ela mesma e o pai atual. Vazio quando a tarefa já é pai — a regra
    /// recusaria de qualquer forma.
    func possibleParents(for task: FocusTask) -> [FocusTask] {
        guard subtaskProgress(of: task).total == 0 else { return [] }
        return TaskTree.topLevel(activeTasks)
            .filter { $0.id != task.id && $0.id != task.parentID }
            .sorted(by: sortOrder.areInIncreasingOrder)
    }

    @discardableResult
    func makeSubtask(_ task: FocusTask, of parent: FocusTask) -> Bool {
        feedback = nil
        do {
            try useCase.makeSubtask(id: task.id, parentID: parent.id)
            expandedTaskIDs.insert(parent.id)
            reload()
            feedback = "\"\(task.title)\" agora é subtarefa de \"\(parent.title)\"."
            return true
        } catch DomainError.taskHasSubtasks {
            feedback = "Não é possível: \"\(task.title)\" já é uma tarefa pai (tem subtarefas)."
        } catch DomainError.subtaskNestingNotAllowed {
            feedback = "Não é possível: \"\(parent.title)\" já é uma subtarefa — só existe um nível."
        } catch DomainError.duplicateEntry(let title) {
            feedback = "Não é possível: \"\(parent.title)\" já tem uma subtarefa ativa chamada \"\(title)\"."
        } catch {
            feedback = "Não foi possível mover: \(error.localizedDescription)"
        }
        return false
    }

    // MARK: - Edição completa (RF-09.6)

    /// Abre o formulário com os valores atuais da tarefa. Clicar numa subtarefa dentro do
    /// formulário do pai troca o editor pelo dela (`onOpenTask`).
    func beginEditing(_ task: FocusTask) {
        feedback = nil
        editor = TaskEditorViewModel(
            task: task, knownTags: knownTags, projects: projects, now: nowProvider, useCase: useCase,
            onChanged: { [weak self] in self?.reload() },
            onClose: { [weak self] in self?.editor = nil },
            onOpenTask: { [weak self] other in self?.beginEditing(other) })
    }

    // MARK: - Prioridade (item 4)

    func setPriority(_ task: FocusTask, _ priority: TaskPriority) {
        feedback = nil
        do {
            try useCase.setPriority(id: task.id, priority: priority)
            reload()
        } catch {
            feedback = "Não foi possível definir a prioridade: \(error.localizedDescription)"
        }
    }

    /// Liga/desliga "Urgente" pelo menu de contexto da linha (RF-09.13).
    func setUrgent(_ task: FocusTask, _ isUrgent: Bool) {
        feedback = nil
        do {
            try useCase.setUrgent(id: task.id, isUrgent)
            reload()
        } catch {
            feedback = "Não foi possível alterar a urgência: \(error.localizedDescription)"
        }
    }

    /// Liga/desliga "Repetir diariamente" pelo menu de contexto da linha (FEAT-004).
    func setRepeatsDaily(_ task: FocusTask, _ repeatsDaily: Bool) {
        feedback = nil
        do {
            try useCase.setRepeatsDaily(id: task.id, repeatsDaily)
            reload()
        } catch {
            feedback = "Não foi possível alterar a repetição: \(error.localizedDescription)"
        }
    }

    // MARK: - Cadastro de tags (item 1)

    /// Quantas tarefas usam cada tag — mostrado no gestor de tags.
    func taskCount(forTag tag: String) -> Int {
        (activeTasks + completedTasks).filter {
            $0.tags.contains { $0.caseInsensitiveCompare(tag) == .orderedSame }
        }.count
    }

    func createTag(_ name: String) {
        feedback = nil
        do { try useCase.createTag(name); reload() }
        catch { feedback = "Não foi possível criar a tag: \(error.localizedDescription)" }
    }

    func renameTag(from oldName: String, to newName: String) {
        feedback = nil
        do {
            try useCase.renameTag(from: oldName, to: newName)
            if tagFilter?.caseInsensitiveCompare(oldName) == .orderedSame { tagFilter = newName }
            reload()
        } catch {
            feedback = "Não foi possível renomear a tag: \(error.localizedDescription)"
        }
    }

    func deleteTag(_ name: String) {
        feedback = nil
        do {
            try useCase.deleteTag(name)
            if tagFilter?.caseInsensitiveCompare(name) == .orderedSame { tagFilter = nil }
            reload()
        } catch {
            feedback = "Não foi possível apagar a tag: \(error.localizedDescription)"
        }
    }

    /// Pai com subtarefas pede confirmação (apagar é em cascata — FEAT-003); o resto apaga direto.
    func delete(_ task: FocusTask) {
        guard !isMutatingTask else { return }
        if subtaskProgress(of: task).total > 0 {
            pendingDeletion = task
        } else {
            performDelete(task)
        }
    }

    /// Tarefa esperando o diálogo "Apagar com as subtarefas?" — `nil` = diálogo fechado.
    @Published var pendingDeletion: FocusTask?

    func confirmPendingDeletion() {
        guard let task = pendingDeletion else { return }
        pendingDeletion = nil
        performDelete(task)
    }

    private func performDelete(_ task: FocusTask) {
        runRowAction(task.id) {
            try self.useCase.deleteTask(id: task.id)
            self.reload()
        } onError: { error in
            "Não foi possível apagar: \(error.localizedDescription)"
        }
    }

    /// Abre o picker: carrega os lembretes não concluídos (todas as listas) e mostra o sheet.
    func prepareImport() async {
        feedback = nil
        accessDenied = false
        reminderSearch = ""
        isImporting = true
        defer { isImporting = false }

        switch await useCase.loadImportableReminders() {
        case .failure(.accessDenied):
            accessDenied = true
            feedback = "Acesso ao Lembretes negado."
        case .failure(.fetchFailed):
            feedback = "Não foi possível ler o Lembretes. Tente novamente."
        case .success(let reminders):
            availableReminders = reminders.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            reload()  // atualiza importedReminderIDs para marcar os já importados
            showsImportSheet = true
        }
    }

    /// Importa um único lembrete escolhido no picker. Dedup segue no use case.
    func importOne(_ reminder: ImportedReminder) async {
        feedback = nil
        let result = await useCase.importReminder(reminder)
        switch result.failure {
        case .accessDenied:
            accessDenied = true
            feedback = "Acesso ao Lembretes negado."
        case .fetchFailed:
            feedback = "Não foi possível salvar. Tente novamente."
        case nil:
            reload()
            if let title = result.importedTitles.first {
                feedback = "Importada: \(title)"
            } else if result.skippedCount > 0 {
                feedback = "\"\(reminder.title)\" já existia."
            }
        }
    }

    /// Ajustes do Sistema › Privacidade e Segurança › Lembretes.
    func openPrivacySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders")!
        NSWorkspace.shared.open(url)
    }
}
