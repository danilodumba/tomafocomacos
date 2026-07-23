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

    // `now` sem default de propósito: `Date()` é proibido na Application (testabilidade) —
    // o Composition Root injeta o relógio real.
    public init(
        tasks: TaskRepository,
        importer: TaskImporting,
        now: @escaping () -> Date,
        makeID: @escaping () -> UUID = { UUID() },
        shouldSyncReminderCompletion: @escaping () -> Bool = { false }
    ) {
        self.tasks = tasks
        self.importer = importer
        self.now = now
        self.makeID = makeID
        self.shouldSyncReminderCompletion = shouldSyncReminderCompletion
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

    /// Substitui as tags de uma tarefa (normalizadas). Tarefa inexistente é no-op.
    public func setTags(id: UUID, tags: [String]) throws {
        try update(id: id) { $0.tags = FocusTask.normalizeTags(tags) }
    }

    /// Todas as tags em uso, ordenadas — alimenta sugestões/filtros na UI.
    public func allTags() throws -> [String] {
        let all = try tasks.loadTasks().flatMap(\.tags)
        return FocusTask.normalizeTags(all).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// Conclui a tarefa e, se a tarefa veio do Lembretes e o toggle está ligado, espelha
    /// a conclusão de volta lá (best-effort — falha de escrita não desfaz a conclusão local).
    public func completeTask(id: UUID) async throws {
        let task = try update(id: id) { $0.completedAt = self.now() }
        await syncReminderCompletion(task, completed: true)
    }

    public func reopenTask(id: UUID) async throws {
        let task = try update(id: id) { $0.completedAt = nil }
        await syncReminderCompletion(task, completed: false)
    }

    private func syncReminderCompletion(_ task: FocusTask?, completed: Bool) async {
        guard shouldSyncReminderCompletion(),
              let task, task.source == .reminders,
              let reminderID = task.reminderID else { return }
        _ = await importer.setReminderCompleted(reminderID: reminderID, completed: completed)
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

    /// Importa UM lembrete escolhido no picker (RF-09.3). Dedup por `reminderID` contra TODAS
    /// as tarefas (não ressuscita concluída); título vazio → ignorado. Não lança.
    public func importReminder(_ reminder: ImportedReminder) async -> ImportTasksResult {
        let title = reminder.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return ImportTasksResult() }
        do {
            var all = try tasks.loadTasks()
            guard !all.contains(where: { $0.reminderID == reminder.reminderID }) else {
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
    /// Dedup por `reminderID`: reimportar nunca duplica.
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
