import Foundation

/// Raia (coluna) do quadro Kanban (FEAT-005). Exatamente uma raia do quadro é a Done
/// (`isDone`): soltar uma tarefa nela conclui a tarefa.
public struct KanbanLane: Equatable, Codable, Sendable, Identifiable {
    public let id: UUID
    public var title: String
    public let isDone: Bool

    public init(id: UUID, title: String, isDone: Bool = false) {
        self.id = id
        self.title = title
        self.isDone = isDone
    }
}
