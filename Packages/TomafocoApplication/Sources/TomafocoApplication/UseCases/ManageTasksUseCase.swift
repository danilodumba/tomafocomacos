import Foundation
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
public final class ManageTasksUseCase {
    private let tasks: TaskRepository
    private let importer: TaskImporting
    private let now: () -> Date
    private let makeID: () -> UUID
    /// Lê o toggle "sincronizar conclusão com o Lembretes" a cada operação (mudar nas
    /// Configurações vale na próxima ação, sem religar). Default `false` nos testes.
    private let shouldSyncReminderCompletion: () -> Bool
    private let tagCatalog: TagCatalog

    // `now` sem default de propósito: `Date()` é proibido na Application (testabilidade) —
    // o Composition Root injeta o relógio real.
    public init(
        tasks: TaskRepository,
        importer: TaskImporting,
        now: @escaping () -> Date,
        makeID: @escaping () -> UUID = { UUID() },
        shouldSyncReminderCompletion: @escaping () -> Bool = { false },
        tagCatalog: TagCatalog = EphemeralTagCatalog()
    ) {
        self.tasks = tasks
        self.importer = importer
        self.now = now
        self.makeID = makeID
        self.shouldSyncReminderCompletion = shouldSyncReminderCompletion
        self.tagCatalog = tagCatalog
    }

    public func allTasks() throws -> [FocusTask] { try tasks.loadTasks() }

    /// Tarefas disponíveis para seleção no timer: não concluídas, mais recentes primeiro.
    public func activeTasks() throws -> [FocusTask] {
        try tasks.loadTasks()
            .filter { !$0.isCompleted }
            .sorted { $0.createdAt > $1.createdAt }
    }

    /// Cria tarefa manual. Lança `emptyTaskTitle` ou `duplicateEntry` (título repetido entre ativas).
    /// `tags` é normalizado (`FocusTask.normalizeTags`) — vazias/duplicatas somem.
    @discardableResult
    public func addTask(title: String, tags: [String] = []) throws -> FocusTask {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw DomainError.emptyTaskTitle }

        var all = try tasks.loadTasks()
        let duplicated = all.contains {
            !$0.isCompleted && $0.title.compare(trimmed, options: [.caseInsensitive]) == .orderedSame
        }
        guard !duplicated else { throw DomainError.duplicateEntry(trimmed) }

        let task = FocusTask(id: makeID(), title: trimmed, source: .manual, createdAt: now(), tags: tags)
        all.append(task)
        try tasks.saveTasks(all)
        return task
    }

    // MARK: - Criação em lote (RF-09.8)

    /// Problemas de cada rascunho, por índice no lote: `emptyTaskTitle`, ou `duplicateEntry`
    /// contra tarefa ATIVA (mesma regra do `addTask`) ou contra uma linha ANTERIOR do próprio
    /// lote — a primeira ocorrência fica válida, as repetições é que acusam. Vazio = lote ok.
    public func validateNewTasks(_ drafts: [NewTaskDraft]) throws -> [Int: DomainError] {
        let activeTitles = try tasks.loadTasks().filter { !$0.isCompleted }.map(\.title)
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
    /// `notes` (vinda da importação do Lembretes) não é editável aqui e fica intacta — o campo
    /// "Observação" saiu do formulário, substituído pelo histórico (FEAT-001).
    /// `dueDate == nil` limpa o vencimento.
    /// **Não** espelha nada de volta no Lembretes: o write-back é só de conclusão — editar aqui
    /// mantém a tarefa local divergente do lembrete de origem de propósito.
    @discardableResult
    public func editTask(
        id: UUID,
        title: String,
        tags: [String],
        dueDate: Date?,
        priority: TaskPriority
    ) throws -> FocusTask? {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { throw DomainError.emptyTaskTitle }

        let all = try tasks.loadTasks()
        guard all.contains(where: { $0.id == id }) else { return nil }
        let duplicated = all.contains {
            $0.id != id && !$0.isCompleted
                && $0.title.compare(trimmedTitle, options: [.caseInsensitive]) == .orderedSame
        }
        guard !duplicated else { throw DomainError.duplicateEntry(trimmedTitle) }

        let normalizedTags = FocusTask.normalizeTags(tags)
        let edited = try update(id: id) {
            $0.title = trimmedTitle
            $0.tags = normalizedTags
            $0.dueDate = dueDate
            $0.priority = priority.rawPriority
        }
        registerInCatalog(normalizedTags)
        return edited
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
        let task = try update(id: id) { $0.completedAt = self.now() }
        return await syncReminderCompletion(task, completed: true)
    }

    @discardableResult
    public func reopenTask(id: UUID) async throws -> ReminderSyncOutcome {
        let task = try update(id: id) { $0.completedAt = nil }
        return await syncReminderCompletion(task, completed: false)
    }

    private func syncReminderCompletion(_ task: FocusTask?, completed: Bool) async -> ReminderSyncOutcome {
        guard shouldSyncReminderCompletion(),
              let task, task.source == .reminders,
              let reminderID = task.reminderID else { return .notApplicable }
        return await importer.setReminderCompleted(reminderID: reminderID, completed: completed)
            ? .synced : .failed
    }

    public func deleteTask(id: UUID) throws {
        var all = try tasks.loadTasks()
        all.removeAll { $0.id == id }
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

    @discardableResult
    private func update(id: UUID, _ mutate: (inout FocusTask) -> Void) throws -> FocusTask? {
        var all = try tasks.loadTasks()
        guard let idx = all.firstIndex(where: { $0.id == id }) else { return nil }
        mutate(&all[idx])
        try tasks.saveTasks(all)
        return all[idx]
    }
}
