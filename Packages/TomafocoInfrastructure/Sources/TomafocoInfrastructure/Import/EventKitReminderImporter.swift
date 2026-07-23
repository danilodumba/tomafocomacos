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
        // `isCompleted = true` já preenche o completionDate; `false` limpa. Best-effort:
        // lembrete apagado no app Lembretes → `calendarItem` devolve nil.
        guard let reminder = store.calendarItem(withIdentifier: reminderID) as? EKReminder else {
            return false
        }
        reminder.isCompleted = completed
        do {
            try store.save(reminder, commit: true)
            return true
        } catch {
            return false
        }
    }
}
#endif
