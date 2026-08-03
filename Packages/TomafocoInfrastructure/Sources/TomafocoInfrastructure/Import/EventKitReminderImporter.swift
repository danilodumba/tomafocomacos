#if canImport(EventKit)
import EventKit
import Foundation
import TomafocoDomain

/// `TaskImporting` sobre o EventKit: lê lembretes não concluídos do app Lembretes (RF-09.3).
/// Sem dedup aqui de propósito — fica no `ManageTasksUseCase`, testável sem EventKit.
public final class EventKitReminderImporter: TaskImporting {

    private let store = EKEventStore()

    public init() {}

    public func requestAccess() async -> Bool {
        // macOS 14 renomeou a API e passou a exigir a usage description "FullAccess".
        if #available(macOS 14.0, *) {
            return (try? await store.requestFullAccessToReminders()) ?? false
        }
        return await withCheckedContinuation { continuation in
            store.requestAccess(to: .reminder) { granted, _ in
                continuation.resume(returning: granted)
            }
        }
    }

    public func fetchReminderLists() async throws -> [ReminderList] {
        store.calendars(for: .reminder).map {
            ReminderList(id: $0.calendarIdentifier, title: $0.title)
        }
    }

    public func fetchIncompleteReminders(fromLists lists: Set<String>?) async throws -> [ImportedReminder] {
        // `calendars: nil` = todas; lista vazia após filtro devolveria TUDO no EventKit,
        // então um filtro que não casa com nada precisa curto-circuitar aqui.
        var calendars: [EKCalendar]?
        if let lists {
            let matched = store.calendars(for: .reminder)
                .filter { lists.contains($0.calendarIdentifier) }
            guard !matched.isEmpty else { return [] }
            calendars = matched
        }
        let predicate = store.predicateForIncompleteReminders(
            withDueDateStarting: nil, ending: nil, calendars: calendars)
        let reminders = await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { found in
                continuation.resume(returning: found ?? [])
            }
        }
        return reminders.map {
            ImportedReminder(
                reminderID: $0.calendarItemIdentifier,
                title: $0.title ?? "",
                listName: $0.calendar?.title ?? "",
                isCompleted: $0.isCompleted,
                notes: $0.notes,
                dueDate: $0.dueDateComponents?.date,
                priority: $0.priority,
                url: $0.url?.absoluteString
            )
        }
    }

    public func setReminderCompleted(reminderID: String, completed: Bool) async -> Bool {
        // Sem pedir acesso NESTE processo o EventKit responde como se o banco estivesse vazio:
        // `calendarItem(withIdentifier:)` devolve nil e a conclusão nunca chegava ao Lembretes.
        // Era o caso comum — concluir uma tarefa numa sessão em que nada foi importado.
        // Já autorizado, `requestFullAccessToReminders` volta na hora e sem prompt.
        guard await requestAccess() else { return false }

        // `isCompleted = true` já preenche o completionDate; `false` limpa. Best-effort:
        // lembrete apagado no app Lembretes → não encontra e devolve `false`.
        guard let reminder = await findReminder(withID: reminderID) else { return false }
        reminder.isCompleted = completed
        do {
            try store.save(reminder, commit: true)
            return true
        } catch {
            return false
        }
    }

    /// Busca o lembrete pelo `calendarItemIdentifier`.
    ///
    /// O caminho direto (`calendarItem(withIdentifier:)`) falha para lembretes em algumas versões
    /// do macOS — daí o plano B varrendo os lembretes de todas as listas (inclusive concluídos,
    /// necessário para reabrir).
    private func findReminder(withID id: String) async -> EKReminder? {
        if let reminder = store.calendarItem(withIdentifier: id) as? EKReminder { return reminder }

        let predicate = store.predicateForReminders(in: nil)
        let all = await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { continuation.resume(returning: $0 ?? []) }
        }
        return all.first { $0.calendarItemIdentifier == id }
    }
}
#endif
