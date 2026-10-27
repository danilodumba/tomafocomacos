import Foundation
import os
import TomafocoDomain

/// Resultado da importação do Lembretes (RF-09.3).
public struct ImportTasksResult: Equatable {
    /// `Error` porque também é o `Failure` do `Result` de `loadReminderLists`.
    public enum Failure: Error, Equatable {
        case accessDenied
        case fetchFailed(String)
    }

    public let importedTitles: [String]
    public let skippedCount: Int
    public let failure: Failure?

    public init(importedTitles: [String] = [], skippedCount: Int = 0, failure: Failure? = nil) {
        self.importedTitles = importedTitles
        self.skippedCount = skippedCount
        self.failure = failure
    }
}

/// O que aconteceu com o espelhamento da conclusão no app Lembretes (RF-09.3).
public enum ReminderSyncOutcome: Equatable, Sendable {
    /// Tarefa manual, ou importada com o toggle de sincronização desligado — nada a espelhar.
    case notApplicable
    case synced
    /// Lembrete apagado no app Lembretes, acesso negado ou falha de gravação.
    case failed
}

/// CRUD de tarefas de foco + importação do Lembretes (RF-09).
/// Persistência falível é engolida com log? Não — aqui os erros de disco sobem para a UI
/// tratar (diferente do coordinator, salvar tarefa é a ação principal, não efeito colateral).
/// Rascunho do formulário de edição (RF-09.6 + RF-09.13) — tudo que o usuário pode mudar de
/// uma vez. Valores crus: quem normaliza (trim, tags, link) é o use case.
public struct TaskEdit: Equatable, Sendable {
    public var title: String
    public var tags: [String]
    public var dueDate: Date?
    public var priority: TaskPriority
    public var repeatsDaily: Bool
    public var notes: String?
    public var link: String?
    public var isUrgent: Bool

    public init(
        title: String, tags: [String] = [], dueDate: Date? = nil, priority: TaskPriority = .none,
        repeatsDaily: Bool = false, notes: String? = nil, link: String? = nil, isUrgent: Bool = false
    ) {
        self.title = title
        self.tags = tags
        self.dueDate = dueDate
        self.priority = priority
        self.repeatsDaily = repeatsDaily
        self.notes = notes
        self.link = link
        self.isUrgent = isUrgent
    }
}

public final class ManageTasksUseCase {
    private let tasks: TaskRepository
    private let importer: TaskImporting
    private let now: () -> Date
    private let makeID: () -> UUID
    /// Lê o toggle "sincronizar conclusão com o Lembretes" a cada operação (mudar nas
    /// Configurações vale na próxima ação, sem religar). Default `false` nos testes.
    private let shouldSyncReminderCompletion: () -> Bool
    private let tagCatalog: TagCatalog
    /// Define o que é "amanhã" para a tarefa diária (FEAT-004). Injetado: testes fixam o fuso.
    private let calendar: Calendar
    /// Quadro Kanban (FEAT-005), só para manter o escopo por tag em dia quando uma tag é
    /// renomeada/apagada. Opcional: sem quadro (testes antigos) as operações de tag seguem iguais.
    private let kanbanBoards: KanbanBoardRepository?
    /// Configuração do app (RF-09.15), só para manter o escopo por tag do seletor do foco em dia
    /// quando uma tag é renomeada/apagada. Opcional pelo mesmo motivo do quadro.
    private let settings: SettingsRepository?
    private static let logger = Logger(subsystem: "com.dsdumba.tomafoco", category: "ManageTasksUseCase")

    // `now` sem default de propósito: `Date()` é proibido na Application (testabilidade) —
    // o Composition Root injeta o relógio real.
    public init(
        tasks: TaskRepository,
        importer: TaskImporting,
        now: @escaping () -> Date,
        makeID: @escaping () -> UUID = { UUID() },
        shouldSyncReminderCompletion: @escaping () -> Bool = { false },
        tagCatalog: TagCatalog = EphemeralTagCatalog(),
        calendar: Calendar = .current,
        kanbanBoards: KanbanBoardRepository? = nil,
        settings: SettingsRepository? = nil
    ) {
        self.tasks = tasks
        self.importer = importer
        self.now = now
        self.makeID = makeID
        self.shouldSyncReminderCompletion = shouldSyncReminderCompletion
        self.tagCatalog = tagCatalog
        self.calendar = calendar
        self.kanbanBoards = kanbanBoards
        self.settings = settings
    }

    public func allTasks() throws -> [FocusTask] { try tasks.loadTasks() }

    /// Tarefas disponíveis para seleção no timer: não concluídas, mais recentes primeiro.
    public func activeTasks() throws -> [FocusTask] {
        try tasks.loadTasks()
            .filter { !$0.isCompleted }
            .sorted { $0.createdAt > $1.createdAt }
    }

    /// Cria tarefa manual de topo. Lança `emptyTaskTitle` ou `duplicateEntry` (título repetido
    /// entre as ativas **de topo** — subtarefa pode repetir título de uma tarefa de topo).
    /// `tags` é normalizado (`FocusTask.normalizeTags`) — vazias/duplicatas somem.
    @discardableResult
    public func addTask(title: String, tags: [String] = []) throws -> FocusTask {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw DomainError.emptyTaskTitle }

        var all = try tasks.loadTasks()
        guard !Self.hasActiveSibling(titled: trimmed, parentID: nil, excluding: nil, in: all) else {
            throw DomainError.duplicateEntry(trimmed)
        }

        let task = FocusTask(id: makeID(), title: trimmed, source: .manual, createdAt: now(), tags: tags)
        all.append(task)
        try tasks.saveTasks(all)
        return task
    }

    // MARK: - Subtarefas (FEAT-003 / RF-09.14)

    /// Cria uma subtarefa: tarefa manual completa com `parentID`. Nasce na raia do pai (Kanban).
    /// Lança `parentTaskNotFound`, `subtaskNestingNotAllowed` (pai já é subtarefa — um nível só),
    /// `emptyTaskTitle` ou `duplicateEntry` (título repetido entre as subtarefas ATIVAS do mesmo
    /// pai — sob outro pai, ou como tarefa de topo, pode repetir).
    ///
    /// **Invariante: subtarefa ativa ⇒ pai ativo.** Pai concluído é reaberto na mesma gravação —
    /// a lista só mostra a filha aninhada no pai, então uma filha ativa sob pai concluído ficaria
    /// invisível com "Mostrar concluídas" desligado. (A reabertura do pai aqui não espelha no
    /// Lembretes: este método é síncrono; o espelhamento segue só em `completeTask`/`reopenTask`.)
    @discardableResult
    public func addSubtask(parentID: UUID, title: String, tags: [String] = []) throws -> FocusTask {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw DomainError.emptyTaskTitle }

        var all = try tasks.loadTasks()
        guard let parentIdx = all.firstIndex(where: { $0.id == parentID }) else { throw DomainError.parentTaskNotFound }
        guard !all[parentIdx].isSubtask else { throw DomainError.subtaskNestingNotAllowed }
        guard !Self.hasActiveSibling(titled: trimmed, parentID: parentID, excluding: nil, in: all) else {
            throw DomainError.duplicateEntry(trimmed)
        }
        if all[parentIdx].isCompleted { applyReopen(to: &all[parentIdx]) }

        let task = FocusTask(
            id: makeID(), title: trimmed, source: .manual, createdAt: now(), tags: tags,
            laneID: all[parentIdx].laneID, parentID: parentID)
        all.append(task)
        try tasks.saveTasks(all)
        registerInCatalog(task.tags)
        return task
    }

    /// Transforma uma tarefa existente em subtarefa de `parentID` (arrastar uma linha sobre a
    /// outra na lista). Vale para tarefa de topo e para subtarefa trocando de pai. Regras:
    /// - `parentTaskNotFound` — pai não existe; tarefa inexistente é no-op (`nil`).
    /// - `taskHasSubtasks` — a tarefa já é pai: levá-la junto com as filhas criaria 2 níveis.
    /// - `subtaskNestingNotAllowed` — o pai já é subtarefa, ou é a própria tarefa.
    /// - `duplicateEntry` — tarefa ativa com título repetido entre as filhas ativas do novo pai.
    /// Mesmo pai de antes → nada muda nem grava. A raia do Kanban é **mantida** (a tarefa já
    /// mora numa raia; só a hierarquia muda — diferente de `addSubtask`, que nasce na do pai).
    /// Invariante "subtarefa ativa ⇒ pai ativo": pai concluído é reaberto na mesma gravação.
    @discardableResult
    public func makeSubtask(id: UUID, parentID: UUID) throws -> FocusTask? {
        var all = try tasks.loadTasks()
        guard let idx = all.firstIndex(where: { $0.id == id }) else { return nil }
        guard let parentIdx = all.firstIndex(where: { $0.id == parentID }) else { throw DomainError.parentTaskNotFound }
        guard !all.contains(where: { $0.parentID == id }) else { throw DomainError.taskHasSubtasks }
        guard id != parentID, !all[parentIdx].isSubtask else { throw DomainError.subtaskNestingNotAllowed }
        if all[idx].parentID == parentID { return all[idx] }
        if !all[idx].isCompleted {
            guard !Self.hasActiveSibling(titled: all[idx].title, parentID: parentID, excluding: id, in: all) else {
                throw DomainError.duplicateEntry(all[idx].title)
            }
            if all[parentIdx].isCompleted { applyReopen(to: &all[parentIdx]) }
        }
        all[idx].parentID = parentID
        try tasks.saveTasks(all)
        return all[idx]
    }

    /// Unicidade de título é por **irmãos ativos**: entre as tarefas de topo (`parentID == nil`)
    /// ou entre as subtarefas do mesmo pai. `excluding` tira a própria tarefa na edição.
    private static func hasActiveSibling(
        titled title: String, parentID: UUID?, excluding id: UUID?, in all: [FocusTask]
    ) -> Bool {
        all.contains {
            $0.id != id && !$0.isCompleted && $0.parentID == parentID
                && $0.title.compare(title, options: [.caseInsensitive]) == .orderedSame
        }
    }

    // MARK: - Criação em lote (RF-09.8)

    /// Problemas de cada rascunho, por índice no lote: `emptyTaskTitle`, ou `duplicateEntry`
    /// contra tarefa ATIVA de topo (mesma regra do `addTask`) ou contra uma linha ANTERIOR do
    /// próprio lote — a primeira ocorrência fica válida, as repetições é que acusam. Vazio = lote ok.
    public func validateNewTasks(_ drafts: [NewTaskDraft]) throws -> [Int: DomainError] {
        let activeTitles = try tasks.loadTasks().filter { !$0.isCompleted && !$0.isSubtask }.map(\.title)
        var seen: [String] = []
        var issues: [Int: DomainError] = [:]
        for (index, draft) in drafts.enumerated() {
            let trimmed = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                issues[index] = .emptyTaskTitle
                continue
            }
            let clashes = { (other: String) in other.compare(trimmed, options: [.caseInsensitive]) == .orderedSame }
            if activeTitles.contains(where: clashes) || seen.contains(where: clashes) {
                issues[index] = .duplicateEntry(trimmed)
            }
            seen.append(trimmed)
        }
        return issues
    }

    /// Cria todas as tarefas do lote numa gravação só. **Atômico**: qualquer rascunho inválido
    /// lança o erro do primeiro e nada é gravado (criar metade e avisar a outra metade deixaria
    /// o usuário sem saber o que sobrou). Tags entram no catálogo, como no `editTask`.
    @discardableResult
    public func addTasks(_ drafts: [NewTaskDraft]) throws -> [FocusTask] {
        guard !drafts.isEmpty else { return [] }
        if let first = try validateNewTasks(drafts).min(by: { $0.key < $1.key }) {
            throw first.value
        }

        let created = drafts.map { draft in
            FocusTask(
                id: makeID(),
                title: draft.title.trimmingCharacters(in: .whitespacesAndNewlines),
                source: .manual,
                createdAt: now(),
                tags: draft.tags,
                dueDate: draft.dueDate,
                priority: draft.priority.rawPriority
            )
        }
        try tasks.saveTasks(try tasks.loadTasks() + created)
        registerInCatalog(created.flatMap(\.tags))
        return created
    }

    /// Edição completa de uma tarefa (RF-09.6): título, tags, vencimento e prioridade
    /// numa transação só — a UI abre um formulário e salva tudo de uma vez.
    ///
    /// Lança `emptyTaskTitle` (título em branco) ou `duplicateEntry` (outra tarefa ATIVA com o
    /// mesmo título — a própria tarefa é excluída da comparação, senão salvar sem mexer no título
    /// acusaria duplicata). Tarefa inexistente é no-op (devolve `nil`).
    ///
    /// Edição **parcial**: nota, link e urgente (RF-09.13) ficam como estão — forma curta para
    /// quem só mexe nos campos originais; o formulário usa `editTask(id:_:)` com `TaskEdit`.
    /// `dueDate == nil` limpa o vencimento.
    /// **Não** espelha nada de volta no Lembretes: o write-back é só de conclusão — editar aqui
    /// mantém a tarefa local divergente do lembrete de origem de propósito.
    @discardableResult
    public func editTask(
        id: UUID,
        title: String,
        tags: [String],
        dueDate: Date?,
        priority: TaskPriority,
        repeatsDaily: Bool = false
    ) throws -> FocusTask? {
        var all = try tasks.loadTasks()
        guard let idx = all.firstIndex(where: { $0.id == id }) else { return nil }
        let current = all[idx]
        return try applyEdit(TaskEdit(
            title: title, tags: tags, dueDate: dueDate, priority: priority, repeatsDaily: repeatsDaily,
            notes: current.notes, link: current.sourceURL, isUrgent: current.isUrgent), at: idx, in: &all)
    }

    /// Edição completa numa transação (RF-09.6 + RF-09.13). Nota em branco vira `nil`; link ganha
    /// `https://` se vier sem esquema e lança `invalidLink` se não for URL. Tarefa inexistente é
    /// no-op (devolve `nil`).
    @discardableResult
    public func editTask(id: UUID, _ edit: TaskEdit) throws -> FocusTask? {
        var all = try tasks.loadTasks()
        guard let idx = all.firstIndex(where: { $0.id == id }) else { return nil }
        return try applyEdit(edit, at: idx, in: &all)
    }

    /// Valida, muta e grava (uma leitura feita por quem chama, uma gravação aqui).
    ///
    /// O link só passa pela normalização/validação quando **mudou**: a tarefa pode ter vindo do
    /// Lembretes com `mailto:`, `tel:` ou `file://` (sem `://` ou sem host) — reprocessar o valor
    /// que já estava gravado reescreveria `mailto:x` como `https://mailto:x` ou impediria salvar
    /// qualquer outro campo até o usuário apagar o link.
    private func applyEdit(_ edit: TaskEdit, at idx: Int, in all: inout [FocusTask]) throws -> FocusTask {
        let trimmedTitle = edit.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { throw DomainError.emptyTaskTitle }
        let current = all[idx]
        let link = edit.link == current.sourceURL ? current.sourceURL : try FocusTask.normalizeLink(edit.link)
        // Duplicata entre irmãos ativos (FEAT-003): o `parentID` não muda na edição.
        guard !Self.hasActiveSibling(titled: trimmedTitle, parentID: current.parentID, excluding: current.id, in: all) else {
            throw DomainError.duplicateEntry(trimmedTitle)
        }

        let normalizedTags = FocusTask.normalizeTags(edit.tags)
        all[idx].title = trimmedTitle
        all[idx].tags = normalizedTags
        all[idx].dueDate = edit.dueDate
        all[idx].priority = edit.priority.rawPriority
        all[idx].repeatsDaily = edit.repeatsDaily
        all[idx].notes = FocusTask.normalizeNotes(edit.notes)
        all[idx].sourceURL = link
        all[idx].isUrgent = edit.isUrgent
        try tasks.saveTasks(all)
        registerInCatalog(normalizedTags)
        return all[idx]
    }

    /// Liga/desliga "Urgente" pelo menu de contexto (RF-09.13). Tarefa inexistente é no-op.
    public func setUrgent(id: UUID, _ isUrgent: Bool) throws {
        try update(id: id) { $0.isUrgent = isUrgent }
    }

    // MARK: - Histórico (FEAT-001)

    /// Acrescenta uma entrada ao histórico da tarefa: data da inclusão (`now`) + descrição.
    /// Descrição em branco lança `DomainError.emptyHistoryEntry`; tarefa inexistente é no-op
    /// (devolve `nil`). Entradas nascem no fim da lista — quem ordena para exibição é a UI.
    @discardableResult
    public func addHistoryEntry(taskID: UUID, text: String) throws -> FocusTask? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw DomainError.emptyHistoryEntry }

        let entry = TaskHistoryEntry(id: makeID(), createdAt: now(), text: trimmed)
        return try update(id: taskID) { $0.history.append(entry) }
    }

    /// Remove UMA entrada do histórico. Entrada ou tarefa inexistente é no-op.
    /// Não existe "editar entrada" de propósito: histórico é log (FEAT-001).
    @discardableResult
    public func deleteHistoryEntry(taskID: UUID, entryID: UUID) throws -> FocusTask? {
        try update(id: taskID) { $0.history.removeAll { $0.id == entryID } }
    }

    /// Substitui as tags de uma tarefa (normalizadas). Tarefa inexistente é no-op.
    /// As tags também entram no catálogo, para reaparecerem no autocomplete mesmo depois de
    /// a tarefa ser apagada.
    public func setTags(id: UUID, tags: [String]) throws {
        let normalized = FocusTask.normalizeTags(tags)
        try update(id: id) { $0.tags = normalized }
        registerInCatalog(normalized)
    }

    /// Define a prioridade de uma tarefa (`TaskPriority`). Tarefa inexistente é no-op.
    public func setPriority(id: UUID, priority: TaskPriority) throws {
        try update(id: id) { $0.priority = priority.rawPriority }
    }

    /// Liga/desliga "Repetir diariamente" (FEAT-004). Desligar não apaga o log de conclusões
    /// nem o histórico. Tarefa inexistente é no-op.
    public func setRepeatsDaily(id: UUID, _ repeatsDaily: Bool) throws {
        try update(id: id) { $0.repeatsDaily = repeatsDaily }
    }

    /// Todas as tags conhecidas (em uso pelas tarefas + catálogo de cadastro), ordenadas —
    /// alimenta sugestões/filtros e a tela de gestão de tags (RF-09.5).
    public func allTags() throws -> [String] {
        let used = try tasks.loadTasks().flatMap(\.tags)
        return FocusTask.normalizeTags(used + tagCatalog.loadTags())
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// Cadastra uma tag "solta" (tela de gestão), mesmo sem tarefa vinculada. No-op se já existe
    /// (comparação por caixa). Lança `emptyTaskTitle` reaproveitado para nome vazio? Não —
    /// nome em branco é simplesmente ignorado.
    public func createTag(_ name: String) throws {
        registerInCatalog([name])
    }

    /// Renomeia uma tag em TODAS as tarefas e no catálogo (RF-09.5). Comparação por caixa.
    /// Renomear para um nome já existente funde as duas (a normalização deduplica).
    public func renameTag(from oldName: String, to newName: String) throws {
        let from = oldName.trimmingCharacters(in: .whitespacesAndNewlines)
        let to = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !from.isEmpty, !to.isEmpty else { return }
        var all = try tasks.loadTasks()
        for idx in all.indices {
            if all[idx].tags.contains(where: { $0.caseInsensitiveCompare(from) == .orderedSame }) {
                let swapped = all[idx].tags.map { $0.caseInsensitiveCompare(from) == .orderedSame ? to : $0 }
                all[idx].tags = FocusTask.normalizeTags(swapped)
            }
        }
        try tasks.saveTasks(all)
        let catalog = tagCatalog.loadTags().map { $0.caseInsensitiveCompare(from) == .orderedSame ? to : $0 }
        tagCatalog.saveTags(FocusTask.normalizeTags(catalog))
        updateScopes { $0.renamingTag(from: from, to: to) }
    }

    /// Remove uma tag de TODAS as tarefas e do catálogo (RF-09.5). Comparação por caixa.
    public func deleteTag(_ name: String) throws {
        let target = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else { return }
        var all = try tasks.loadTasks()
        for idx in all.indices {
            all[idx].tags.removeAll { $0.caseInsensitiveCompare(target) == .orderedSame }
        }
        try tasks.saveTasks(all)
        tagCatalog.saveTags(tagCatalog.loadTags().filter { $0.caseInsensitiveCompare(target) != .orderedSame })
        updateScopes { $0.removingTag(target) }
    }

    /// Reescreve os escopos por tag — do quadro (FEAT-005) e do seletor do foco (RF-09.15).
    /// Best-effort: a operação de tag já foi gravada nas tarefas e não é desfeita se um deles
    /// falhar — só fica no log.
    private func updateScopes(_ transform: (TaskScope) -> TaskScope) {
        if let kanbanBoards {
            do {
                if var board = try kanbanBoards.loadBoard() {
                    let scope = transform(board.taskScope)
                    if scope != board.taskScope {
                        board.taskScope = scope
                        try kanbanBoards.saveBoard(board)
                    }
                }
            } catch {
                Self.logger.error("Falha ao atualizar o escopo do Kanban: \(String(describing: error), privacy: .public)")
            }
        }
        if let settings {
            var config = settings.loadConfiguration()
            let scope = transform(config.focusTaskScope)
            if scope != config.focusTaskScope {
                config.focusTaskScope = scope
                settings.save(config)
            }
        }
    }

    /// Une `newTags` ao catálogo, normalizado e deduplicado por caixa.
    private func registerInCatalog(_ newTags: [String]) {
        let merged = FocusTask.normalizeTags(tagCatalog.loadTags() + newTags)
        tagCatalog.saveTags(merged)
    }

    /// Conclui a tarefa e, se a tarefa veio do Lembretes e o toggle está ligado, espelha
    /// a conclusão de volta lá (best-effort — falha de escrita não desfaz a conclusão local).
    /// O resultado é devolvido para a UI poder avisar que o espelhamento não foi (silêncio aqui
    /// virava "concluí no Tomafoco e no Lembretes não mudou nada, sem explicação").
    @discardableResult
    public func completeTask(id: UUID) async throws -> ReminderSyncOutcome {
        var all = try tasks.loadTasks()
        guard let task = applyCompletionCascade(id: id, in: &all) else { return .notApplicable }
        try tasks.saveTasks(all)
        return await syncCompletion(of: task)
    }

    /// Reabre a tarefa. Subtarefa (FEAT-003) reabre também o pai concluído — invariante
    /// "subtarefa ativa ⇒ pai ativo" (ver `addSubtask`). O espelhamento no Lembretes cobre os
    /// dois; se qualquer um falhar, devolve `.failed`.
    @discardableResult
    public func reopenTask(id: UUID) async throws -> ReminderSyncOutcome {
        var all = try tasks.loadTasks()
        guard let (task, parent) = applyReopenCascade(id: id, in: &all) else { return .notApplicable }
        try tasks.saveTasks(all)
        let outcome = await syncCompletion(of: task)
        guard let parent else { return outcome }
        let parentOutcome = await syncCompletion(of: parent)
        if outcome == .failed || parentOutcome == .failed { return .failed }
        return outcome == .notApplicable ? parentOutcome : outcome
    }

    /// Reabrir sem I/O: a tarefa e, se ela é subtarefa com pai concluído, o pai. Devolve
    /// `(tarefa, pai reaberto ou nil)`; `nil` se a tarefa não existe. `internal`: o
    /// `ManageKanbanUseCase` aplica junto com a troca de raia numa gravação só.
    func applyReopenCascade(id: UUID, in all: inout [FocusTask]) -> (task: FocusTask, reopenedParent: FocusTask?)? {
        guard let idx = all.firstIndex(where: { $0.id == id }) else { return nil }
        applyReopen(to: &all[idx])
        guard let parentID = all[idx].parentID,
              let parentIdx = all.firstIndex(where: { $0.id == parentID }),
              all[parentIdx].isCompleted else { return (all[idx], nil) }
        applyReopen(to: &all[parentIdx])
        return (all[idx], all[parentIdx])
    }

    /// Concluir com **cascata** (FEAT-003), sem I/O: fecha a tarefa e as subtarefas ainda
    /// abertas (as já concluídas mantêm a data). Reabrir não tem cascata.
    /// Diária (FEAT-004): a tarefa fecha como qualquer outra e um **clone** para amanhã
    /// (`FocusTask.nextDailyOccurrence`) entra no fim da lista. Só a tarefa concluída
    /// diretamente é clonada — filha diária fechada pela cascata do pai não gera clone (o pai
    /// acabou; um clone dela ficaria órfão de pai ativo, violando "subtarefa ativa ⇒ pai ativo").
    /// Devolve a tarefa gravada ou `nil` se não existe.
    /// `internal`: o `ManageKanbanUseCase` aplica junto com a troca de raia numa gravação só.
    @discardableResult
    func applyCompletionCascade(id: UUID, in all: inout [FocusTask]) -> FocusTask? {
        guard let idx = all.firstIndex(where: { $0.id == id }) else { return nil }
        let completedAt = now()
        all[idx].completedAt = completedAt
        for child in all.indices where all[child].parentID == id && !all[child].isCompleted {
            all[child].completedAt = completedAt
        }
        if all[idx].repeatsDaily {
            all.append(all[idx].nextDailyOccurrence(id: makeID(), now: completedAt, calendar: calendar))
        }
        return all[idx]
    }

    /// Reabrir não reabre as subtarefas (FEAT-003): o usuário reabre à mão o que quiser refazer.
    func applyReopen(to task: inout FocusTask) {
        task.completedAt = nil
    }

    /// Espelha no Lembretes o estado de conclusão que a tarefa tem AGORA (best-effort). Vale
    /// também para a diária: ela fecha de verdade, então o lembrete fecha junto (num lembrete
    /// recorrente, o próprio Lembretes avança para a próxima ocorrência).
    func syncCompletion(of task: FocusTask?) async -> ReminderSyncOutcome {
        guard let task else { return .notApplicable }
        return await syncReminderCompletion(task, completed: task.isCompleted)
    }

    private func syncReminderCompletion(_ task: FocusTask?, completed: Bool) async -> ReminderSyncOutcome {
        guard shouldSyncReminderCompletion(),
              let task, task.source == .reminders,
              let reminderID = task.reminderID else { return .notApplicable }
        return await importer.setReminderCompleted(reminderID: reminderID, completed: completed)
            ? .synced : .failed
    }

    /// Apaga a tarefa e, em **cascata**, as subtarefas dela (FEAT-003) — subtarefa sem pai não
    /// faz sentido. A UI pede confirmação quando há filhas. Tarefa inexistente é no-op.
    public func deleteTask(id: UUID) throws {
        var all = try tasks.loadTasks()
        all.removeAll { $0.id == id || $0.parentID == id }
        try tasks.saveTasks(all)
    }

    /// Listas do Lembretes disponíveis para o filtro de importação (RF-09.3).
    public func loadReminderLists() async -> Result<[ReminderList], ImportTasksResult.Failure> {
        guard await importer.requestAccess() else { return .failure(.accessDenied) }
        do {
            return .success(try await importer.fetchReminderLists())
        } catch {
            return .failure(.fetchFailed(String(describing: error)))
        }
    }

    /// Lembretes não concluídos disponíveis para escolha individual no picker (RF-09.3).
    /// Não filtra os já importados — quem chama marca/desabilita comparando `reminderID`
    /// com as tarefas existentes (`allTasks`). `lists == nil` = todas as listas.
    public func loadImportableReminders(
        fromLists lists: Set<String>? = nil
    ) async -> Result<[ImportedReminder], ImportTasksResult.Failure> {
        guard await importer.requestAccess() else { return .failure(.accessDenied) }
        do {
            return .success(try await importer.fetchIncompleteReminders(fromLists: lists))
        } catch {
            return .failure(.fetchFailed(String(describing: error)))
        }
    }

    /// Importa UM lembrete escolhido no picker (RF-09.3). Título vazio → ignorado. Não lança.
    ///
    /// Dedup por `reminderID` só contra as tarefas **ativas**: com a cópia local já concluída,
    /// o mesmo lembrete pode voltar como nova tarefa. É o caso do lembrete **recorrente** —
    /// concluir a ocorrência de hoje não pode impedir de puxar a de amanhã. Cada importação vira
    /// uma tarefa nova (`id` próprio), então o histórico da ocorrência anterior fica preservado.
    public func importReminder(_ reminder: ImportedReminder) async -> ImportTasksResult {
        let title = reminder.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return ImportTasksResult() }
        do {
            var all = try tasks.loadTasks()
            guard !all.contains(where: { $0.reminderID == reminder.reminderID && !$0.isCompleted }) else {
                return ImportTasksResult(skippedCount: 1)
            }
            all.append(makeFocusTask(from: reminder, title: title))
            try tasks.saveTasks(all)
            return ImportTasksResult(importedTitles: [title])
        } catch {
            return ImportTasksResult(failure: .fetchFailed(String(describing: error)))
        }
    }

    /// Cria a `FocusTask` a partir de um lembrete, mapeando os campos ricos.
    /// `priority == 0` (nenhuma, no EventKit) vira `nil`.
    private func makeFocusTask(from reminder: ImportedReminder, title: String) -> FocusTask {
        FocusTask(
            id: makeID(), title: title, source: .reminders,
            reminderID: reminder.reminderID, createdAt: now(),
            notes: reminder.notes,
            dueDate: reminder.dueDate,
            priority: reminder.priority == 0 ? nil : reminder.priority,
            sourceURL: reminder.url
        )
    }

    /// Importa lembretes não concluídos — de todas as listas (`nil`) ou só das indicadas.
    /// Dedup por `reminderID` contra TODAS as tarefas, inclusive concluídas: reimportar nunca
    /// duplica. Diferente do `importReminder` de propósito — aqui o usuário não escolhe item a
    /// item, então recorrência precisa ser pedida no picker; senão um lote traria de volta tudo
    /// que já foi concluído por aqui.
    /// Não lança — falha vira `ImportTasksResult.failure` para a UI narrar sem try/catch.
    public func importFromReminders(fromLists lists: Set<String>? = nil) async -> ImportTasksResult {
        guard await importer.requestAccess() else {
            return ImportTasksResult(failure: .accessDenied)
        }

        let reminders: [ImportedReminder]
        do {
            reminders = try await importer.fetchIncompleteReminders(fromLists: lists)
        } catch {
            return ImportTasksResult(failure: .fetchFailed(String(describing: error)))
        }

        do {
            var all = try tasks.loadTasks()
            // Dedup contra TODAS as tarefas (inclusive concluídas): concluir aqui e reimportar
            // não pode ressuscitar a tarefa.
            let known = Set(all.compactMap(\.reminderID))
            var imported: [String] = []
            var skipped = 0

            for reminder in reminders {
                let title = reminder.title.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !title.isEmpty else { continue }
                guard !known.contains(reminder.reminderID) else {
                    skipped += 1
                    continue
                }
                all.append(makeFocusTask(from: reminder, title: title))
                imported.append(title)
            }

            if !imported.isEmpty { try tasks.saveTasks(all) }
            return ImportTasksResult(importedTitles: imported, skippedCount: skipped)
        } catch {
            return ImportTasksResult(failure: .fetchFailed(String(describing: error)))
        }
    }

    /// Grava a lista inteira de uma vez (FEAT-005: apagar raia reescreve N tarefas numa só
    /// gravação). `internal` — só o `ManageKanbanUseCase` usa.
    func replaceAll(_ all: [FocusTask]) throws {
        try tasks.saveTasks(all)
    }

    /// Aplica `mutate` a uma tarefa e grava. Tarefa inexistente é no-op (`nil`).
    /// `internal`: o `ManageKanbanUseCase` grava raia + histórico por aqui (FEAT-005).
    @discardableResult
    func update(id: UUID, _ mutate: (inout FocusTask) -> Void) throws -> FocusTask? {
        var all = try tasks.loadTasks()
        guard let idx = all.firstIndex(where: { $0.id == id }) else { return nil }
        mutate(&all[idx])
        try tasks.saveTasks(all)
        return all[idx]
    }
}
