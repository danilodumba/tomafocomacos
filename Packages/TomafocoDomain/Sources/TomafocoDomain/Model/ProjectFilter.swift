import Foundation

/// Recorte por projeto (FEAT-006). Na barra da lista e do quadro é recorte de sessão (não
/// persistido); no escopo de um quadro Kanban (FEAT-008, `KanbanBoard.projectScope`) é gravado.
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

// Codable manual (`mode` + `projectID`), mesmo formato do `TaskScope`: JSON legível e estável.
// Modo desconhecido ou `project` sem id → `all` (nunca lança — lançar descartaria o quadro).
extension ProjectFilter: Codable {
    private enum CodingKeys: String, CodingKey { case mode, projectID }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decodeIfPresent(String.self, forKey: .mode) {
        case "none":
            self = .none
        case "project":
            if let id = try? c.decodeIfPresent(UUID.self, forKey: .projectID) {
                self = .project(id)
            } else {
                self = .all
            }
        default:
            self = .all
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .all:
            try c.encode("all", forKey: .mode)
        case .none:
            try c.encode("none", forKey: .mode)
        case .project(let id):
            try c.encode("project", forKey: .mode)
            try c.encode(id, forKey: .projectID)
        }
    }
}
