import Foundation
import TomafocoDomain
import TomafocoApplication

/// ViewModel da janela Kanban (FEAT-005): colunas filtradas/ordenadas, movimentação entre raias
/// e criação rápida. Configuração do quadro (raias, dias no Done, escopo por tag) fica nas
/// Configurações › Kanban (`KanbanSettingsViewModel`).
@MainActor
final class KanbanViewModel: ObservableObject, TaskRowActionRunning {

    @Published private(set) var board: KanbanBoard?
    @Published private(set) var tasks: [FocusTask] = []
    @Published private(set) var knownTags: [String] = []

    // Filtros da barra — recorte da sessão, independentes dos da lista (não persistidos).
    @Published var searchText = ""
    @Published var tagFilter: String?
    @Published var dueFilter: TaskDueFilter = .all
    /// Persistida, separada da ordenação da lista.
    @Published var sortOrder: TaskSortOrder = .createdAt {
        didSet { defaults.set(sortOrder.rawValue, forKey: Self.sortOrderKey) }
    }

    @Published var newTitle = ""
    /// Tag da nova tarefa. Com escopo por tag, já vem com a 1ª tag do escopo — senão a tarefa
    /// nasceria fora do quadro e sumiria ao criar.
    @Published var newTag: String?

    @Published var editor: TaskEditorViewModel?
    @Published var feedback: String?
    @Published var busyTaskIDs: Set<UUID> = []

    private let useCase: ManageKanbanUseCase
    private let manageTasks: ManageTasksUseCase
    private let defaults: UserDefaults
    /// Avisa que as tarefas mudaram por aqui — a lista e o seletor do timer recarregam.
    private let onTasksChanged: () -> Void
    private static let sortOrderKey = "kanbanSortOrder"

    init(useCase: ManageKanbanUseCase, manageTasks: ManageTasksUseCase,
         defaults: UserDefaults = .standard, onTasksChanged: @escaping () -> Void) {
        self.useCase = useCase
        self.manageTasks = manageTasks
        self.defaults = defaults
        self.onTasksChanged = onTasksChanged
        sortOrder = TaskSortOrder.stored(in: defaults, key: Self.sortOrderKey)
        // Sem `refresh()` aqui de propósito: o VM nasce no lançamento, mas a janela pode nunca
        // abrir — a primeira leitura fica para o `onAppear` (`didAppear`).
    }

    /// A janela está na tela. Fora dela o relay não manda `refresh()` (leitura de disco à toa
    /// a cada mudança na lista); ao reaparecer, relê tudo.
    private(set) var isPresented = false

    func didAppear() {
        isPresented = true
        refresh()
    }

    func didDisappear() {
        isPresented = false
    }

    /// Só relê (quadro, tarefas, tags). Chamado pelas outras janelas quando a mudança veio delas.
    func refresh() {
        do {
            board = try useCase.board()
        } catch {
            feedback = "Não foi possível abrir o quadro: \(error.localizedDescription)"
        }
        tasks = (try? manageTasks.allTasks()) ?? []
        knownTags = (try? manageTasks.allTags()) ?? []

        let options = tagFilterOptions
        if let tag = tagFilter, !options.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) {
            tagFilter = nil
        }
        if let tag = newTag, !options.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) {
            newTag = nil
        }
        if newTag == nil, case .tags(let selected)? = board?.taskScope { newTag = selected.first }
        if let editor, !tasks.contains(where: { $0.id == editor.task.id }) { self.editor = nil }
    }

    /// Relê e avisa as outras telas — depois de toda mudança feita aqui.
    private func reload() {
        refresh()
        onTasksChanged()
    }

    // MARK: - Exibição

    /// Colunas na ordem das raias: escopo + prazo da Done (Domain), filtros da barra e ordenação.
    /// Na Done, concluídas mais recentes primeiro (vencimento/prioridade não dizem nada ali).
    var columns: [KanbanColumn] {
        guard let board else { return [] }
        let filter = TaskFilter(searchText: searchText, tag: tagFilter, due: dueFilter)
        // Subtarefa (FEAT-003) passa se ela ou o pai passa — filtrar pela tag do pai não pode
        // esconder as filhas que estão na mesma raia.
        let visible = tasks.filter {
            filter.matchesCard($0, parent: TaskTree.parent(of: $0, in: tasks), now: Date(), calendar: .current)
        }
        // `among: tasks`: a herança do escopo procura o pai na lista CHEIA — buscar pelo nome
        // da filha tira o pai de `visible`, e a filha não pode sumir do quadro por isso.
        return board.columns(for: visible, among: tasks, now: Date(), calendar: .current).map { column in
            let sorted = column.lane.isDone
                ? column.tasks.sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
                : column.tasks.sorted(by: sortOrder.areInIncreasingOrder)
            return KanbanColumn(lane: column.lane, tasks: sorted)
        }
    }

    /// Tags oferecidas no filtro e na criação: as do escopo, ou todas no modo "todas as tarefas".
    var tagFilterOptions: [String] {
        guard case .tags(let selected)? = board?.taskScope else { return knownTags }
        return selected
    }

    var scopeIsByTag: Bool {
        if case .tags? = board?.taskScope { return true }
        return false
    }

    /// Escopo por tag sem nenhuma tag marcada — quadro vazio de propósito, a UI explica.
    var scopeHasNoTags: Bool { board?.taskScope == .tags([]) }

    var hasActiveFilters: Bool {
        !searchText.trimmingCharacters(in: .whitespaces).isEmpty || tagFilter != nil || dueFilter != .all
    }

    // MARK: - Subtarefas (FEAT-003)

    /// Título do pai para o chip "↳ Pai" no cartão da subtarefa.
    func parentTitle(of task: FocusTask) -> String? {
        TaskTree.parent(of: task, in: tasks)?.title
    }

    func subtaskProgress(of task: FocusTask) -> (done: Int, total: Int) {
        TaskTree.progress(of: task.id, in: tasks)
    }

    // MARK: - Movimentação

    /// Move pelo menu "Mover para" ou pelo arraste. Mesma raia é no-op (sem histórico).
    func move(_ task: FocusTask, to lane: KanbanLane) {
        guard let board, board.lane(for: task).id != lane.id else { return }
        runRowAction(task.id) {
            let outcome = try await self.useCase.moveTask(id: task.id, toLane: lane.id)
            self.reload()
            // Diária (FEAT-004): o cartão vai para a Done e um clone aparece na 1ª raia. O aviso
            // que existia aqui foi removido a pedido do usuário (2026-10-27) — o clone na 1ª raia
            // já é visível por si.
            if outcome == .failed {
                self.feedback = "Tarefa movida aqui, mas não foi possível refletir no Lembretes"
                    + " (lembrete apagado ou acesso negado em Ajustes › Privacidade › Lembretes)."
            }
        } onError: { error in
            "Não foi possível mover: \(error.localizedDescription)"
        }
    }

    /// Soltar na coluna. O payload é texto: o arraste pode vir de fora do app, então só um
    /// UUID de tarefa existente conta — o resto é recusado. Com outra movimentação em curso (ou
    /// no cooldown) o drop é recusado de cara: aceitar e não mover deixaria o usuário achando
    /// que a tarefa foi.
    func handleDrop(_ items: [String], on lane: KanbanLane) -> Bool {
        guard !isMutatingTask,
              let task = items.lazy.compactMap(UUID.init(uuidString:))
                  .compactMap({ id in self.tasks.first { $0.id == id } }).first,
              let board, board.lane(for: task).id != lane.id else { return false }
        move(task, to: lane)
        return true
    }

    // MARK: - Criação e edição

    /// Criar pelo quadro só faz sentido se a tarefa nova for aparecer nele: com escopo por tag
    /// ela precisa nascer com uma tag do escopo.
    var canAddTask: Bool {
        guard !newTitle.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        guard scopeIsByTag else { return true }
        return newTag.map { tag in tagFilterOptions.contains { $0.caseInsensitiveCompare(tag) == .orderedSame } } ?? false
    }

    /// Cria na primeira raia, com a tag escolhida (a do escopo, por padrão).
    func addTask() {
        feedback = nil
        guard canAddTask else {
            if scopeIsByTag && !newTitle.trimmingCharacters(in: .whitespaces).isEmpty {
                feedback = scopeHasNoTags
                    ? "Nenhuma tag selecionada — ajuste em Configurações › Kanban antes de criar pelo quadro."
                    : "Escolha uma tag do quadro para a nova tarefa."
            }
            return
        }
        do {
            try manageTasks.addTask(title: newTitle, tags: newTag.map { [$0] } ?? [])
            newTitle = ""
            reload()
        } catch DomainError.emptyTaskTitle {
            feedback = "Informe um título para a tarefa."
        } catch DomainError.duplicateEntry(let title) {
            feedback = "Já existe uma tarefa ativa chamada \"\(title)\"."
        } catch {
            feedback = "Não foi possível salvar: \(error.localizedDescription)"
        }
    }

    func beginEditing(_ task: FocusTask) {
        feedback = nil
        editor = TaskEditorViewModel(
            task: task, knownTags: knownTags, useCase: manageTasks,
            onChanged: { [weak self] in
                guard let self else { return }
                self.reload()
                // Tirar a tag do escopo pelo formulário faz o cartão sumir — avisar o porquê.
                // Com herança (FEAT-003): filha sem tag sob pai no escopo continua no quadro.
                if let board = self.board, let saved = self.tasks.first(where: { $0.id == task.id }),
                   !board.taskScope.includes(saved, in: self.tasks) {
                    self.feedback = "\"\(saved.title)\" saiu do quadro (sem tag do escopo)."
                }
            },
            onClose: { [weak self] in self?.editor = nil },
            onOpenTask: { [weak self] other in self?.beginEditing(other) })
    }

    /// Liga/desliga "Urgente" pelo menu de contexto do cartão (RF-09.13).
    func setUrgent(_ task: FocusTask, _ isUrgent: Bool) {
        feedback = nil
        do {
            try manageTasks.setUrgent(id: task.id, isUrgent)
            reload()
        } catch {
            feedback = "Não foi possível alterar a urgência: \(error.localizedDescription)"
        }
    }
}
