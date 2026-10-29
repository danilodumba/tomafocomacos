import Foundation

/// Recorte da lista e do quadro por projeto (FEAT-006). Recorte de sessão — não persistido.
public enum ProjectFilter: Equatable, Hashable, Sendable {
    case all
    /// Só tarefas sem projeto.
    case none
    case project(UUID)

    public func matches(_ task: FocusTask) -> Bool {
        switch self {
        case .all: return true
        case .none: return task.projectID == nil
        case .project(let id): return task.projectID == id
        }
    }

    /// Projeto em que uma tarefa criada com este filtro ativo deve nascer — senão ela sumiria
    /// da tela ao criar.
    public var projectIDForNewTask: UUID? {
        if case .project(let id) = self { return id }
        return nil
    }
}
