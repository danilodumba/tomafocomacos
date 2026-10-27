import Foundation
import TomafocoDomain

/// Recorte de tarefas usado pela lista e pelo quadro Kanban (FEAT-005): busca por título,
/// tag, prioridade e vencimento. Puro — a mesma semântica nas duas janelas, cada uma com o
/// seu estado de filtro.
public struct TaskFilter: Equatable, Sendable {
    public var searchText: String
    public var tag: String?
    public var priority: TaskPriority?
    public var due: TaskDueFilter

    public init(searchText: String = "", tag: String? = nil, priority: TaskPriority? = nil,
                due: TaskDueFilter = .all) {
        self.searchText = searchText
        self.tag = tag
        self.priority = priority
        self.due = due
    }

    /// Título contém a busca (sem caixa/acento do locale), tag igual sem caixa, prioridade
    /// exata e vencimento conforme `TaskDueFilter`. Critério vazio não filtra.
    public func matches(_ task: FocusTask, now: Date, calendar: Calendar) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty && !task.title.localizedCaseInsensitiveContains(query) { return false }
        if let tag, !task.tags.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) { return false }
        if let priority, TaskPriority(rawPriority: task.priority) != priority { return false }
        return due.matches(task, now: now, calendar: calendar)
    }

    public func apply(_ tasks: [FocusTask], now: Date, calendar: Calendar) -> [FocusTask] {
        tasks.filter { matches($0, now: now, calendar: calendar) }
    }

    /// Recorte da lista aninhada (FEAT-003): a tarefa de topo entra se ela **ou alguma
    /// subtarefa** casa — achar a tarefa pelo passo. Subtarefa sozinha não vira linha de topo.
    public func matchesTree(_ task: FocusTask, children: [FocusTask], now: Date, calendar: Calendar) -> Bool {
        matches(task, now: now, calendar: calendar)
            || children.contains { matches($0, now: now, calendar: calendar) }
    }

    /// Cartão do quadro (FEAT-003): subtarefa passa se ela ou o pai passa — filtrar por tag do
    /// pai não pode esconder as filhas que estão na mesma raia.
    public func matchesCard(_ task: FocusTask, parent: FocusTask?, now: Date, calendar: Calendar) -> Bool {
        matches(task, now: now, calendar: calendar)
            || parent.map { matches($0, now: now, calendar: calendar) } == true
    }
}
