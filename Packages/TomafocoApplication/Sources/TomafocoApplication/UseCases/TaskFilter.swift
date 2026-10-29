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
    /// Projeto (FEAT-006). Passa entre pai e filha como busca/tag — mas subtarefa tem sempre o
    /// projeto do pai, então na prática tanto faz.
    public var project: ProjectFilter

    public init(searchText: String = "", tag: String? = nil, priority: TaskPriority? = nil,
                due: TaskDueFilter = .all, project: ProjectFilter = .all) {
        self.searchText = searchText
        self.tag = tag
        self.priority = priority
        self.due = due
        self.project = project
    }

    /// Título contém a busca (sem caixa/acento do locale), tag igual sem caixa, prioridade
    /// exata, projeto e vencimento conforme `TaskDueFilter`. Critério vazio não filtra.
    public func matches(_ task: FocusTask, now: Date, calendar: Calendar) -> Bool {
        matcher(now: now, calendar: calendar)(task)
    }

    public func apply(_ tasks: [FocusTask], now: Date, calendar: Calendar) -> [FocusTask] {
        tasks.filter(matcher(now: now, calendar: calendar))
    }

    /// Recorte da lista aninhada (FEAT-003): a tarefa de topo entra se ela **ou alguma
    /// subtarefa** casa — achar a tarefa pelo passo. Subtarefa sozinha não vira linha de topo.
    public func matchesTree(_ task: FocusTask, children: [FocusTask], now: Date, calendar: Calendar) -> Bool {
        let matches = matcher(now: now, calendar: calendar)
        return matches(task) || children.contains(where: matches)
    }

    /// Cartão do quadro (FEAT-003): subtarefa passa na busca/tag/prioridade se ela ou o pai
    /// passa — filtrar por tag do pai não pode esconder as filhas que estão na mesma raia.
    /// **Vencimento (FEAT-006):** filha **com** vencimento é julgada só pelo dela (pai atrasado
    /// não a leva para "Atrasadas"); filha **sem** vencimento herda a **data** do pai — é o que
    /// a lista faz (mostra todas as filhas sob o pai que casou). A **conclusão** é sempre a do
    /// cartão: filha concluída não vira "atrasada" porque o pai ainda está aberto.
    public func matchesCard(_ task: FocusTask, parent: FocusTask?, now: Date, calendar: Calendar) -> Bool {
        var dueSubject = task
        if task.dueDate == nil, let parent { dueSubject.dueDate = parent.dueDate }
        guard due.matches(dueSubject, now: now, calendar: calendar) else { return false }
        let query = trimmedQuery
        return matchesAttributes(task, query: query)
            || parent.map { matchesAttributes($0, query: query) } == true
    }

    // MARK: - Critérios

    /// A regra completa (atributos + vencimento) com a busca trimada **uma vez** — todos os
    /// caminhos passam por aqui, então critério novo entra num lugar só.
    private func matcher(now: Date, calendar: Calendar) -> (FocusTask) -> Bool {
        let query = trimmedQuery
        return { task in
            self.matchesAttributes(task, query: query) && self.due.matches(task, now: now, calendar: calendar)
        }
    }

    private var trimmedQuery: String { searchText.trimmingCharacters(in: .whitespaces) }

    /// Busca, tag, prioridade e projeto — os critérios que "passam" entre pai e filha. `query` já vem
    /// trimada (uma vez por recorte, não por tarefa).
    private func matchesAttributes(_ task: FocusTask, query: String) -> Bool {
        if !query.isEmpty && !task.title.localizedCaseInsensitiveContains(query) { return false }
        if let tag, !task.tags.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) { return false }
        if let priority, TaskPriority(rawPriority: task.priority) != priority { return false }
        return project.matches(task)
    }
}
