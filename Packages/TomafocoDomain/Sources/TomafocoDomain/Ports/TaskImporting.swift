import Foundation

/// Lembrete lido da fonte externa (app Lembretes), ainda sem identidade interna.
public struct ImportedReminder: Equatable, Sendable, Identifiable {
    public let reminderID: String
    public let title: String
    public let listName: String
    public let isCompleted: Bool
    /// `EKReminder.notes` — texto livre do lembrete.
    public let notes: String?
    /// `EKReminder.dueDateComponents?.date` — vencimento, se houver.
    public let dueDate: Date?
    /// `EKReminder.priority` (0 = nenhuma; 1–9 = alta→baixa).
    public let priority: Int
    /// `EKReminder.url?.absoluteString` — link que o usuário anexou ao lembrete.
    public let url: String?

    /// `id` = `reminderID` (Identifiable para uso direto em `List`/`ForEach`).
    public var id: String { reminderID }

    public init(
        reminderID: String,
        title: String,
        listName: String,
        isCompleted: Bool,
        notes: String? = nil,
        dueDate: Date? = nil,
        priority: Int = 0,
        url: String? = nil
    ) {
        self.reminderID = reminderID
        self.title = title
        self.listName = listName
        self.isCompleted = isCompleted
        self.notes = notes
        self.dueDate = dueDate
        self.priority = priority
        self.url = url
    }
}

/// Uma lista do app Lembretes (RF-09.3). Tags do Lembretes NÃO existem no EventKit —
/// a lista é a única unidade de filtro que a API expõe.
public struct ReminderList: Equatable, Sendable, Identifiable {
    /// `calendarIdentifier` do EventKit.
    public let id: String
    public let title: String

    public init(id: String, title: String) {
        self.id = id
        self.title = title
    }
}

/// Importação de tarefas de fonte externa (EventKit no adapter real).
/// A dedup contra tarefas já importadas NÃO é responsabilidade daqui — fica no use case,
/// onde é testável sem EventKit.
public protocol TaskImporting: AnyObject {
    /// Pede acesso ao usuário (prompt TCC). `false` = negado — o chamador orienta o usuário
    /// a liberar em Ajustes do Sistema.
    func requestAccess() async -> Bool
    func fetchReminderLists() async throws -> [ReminderList]
    /// `lists == nil` → todas as listas.
    func fetchIncompleteReminders(fromLists lists: Set<String>?) async throws -> [ImportedReminder]
    /// Escreve a conclusão de volta no lembrete de origem (RF-09.3). Best-effort:
    /// `false` = lembrete não encontrado (apagado no app Lembretes) ou falha de gravação.
    func setReminderCompleted(reminderID: String, completed: Bool) async -> Bool
}
