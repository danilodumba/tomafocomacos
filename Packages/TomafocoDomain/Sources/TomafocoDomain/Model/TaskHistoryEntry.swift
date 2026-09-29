import Foundation

/// Uma entrada do histórico de uma tarefa (FEAT-001): data da inclusão + descrição.
///
/// É **log**: nasce, pode ser apagada, mas não é editada — por isso `id`/`createdAt` são `let`.
/// A descrição chega já trimada pelo use case (`ManageTasksUseCase.addHistoryEntry`), que também
/// rejeita texto em branco.
public struct TaskHistoryEntry: Equatable, Codable, Sendable, Identifiable {
    public let id: UUID
    /// Data da inclusão. Injetada pelo use case — `Date()` é proibido no Domain/Application.
    public let createdAt: Date
    public let text: String

    public init(id: UUID, createdAt: Date, text: String) {
        self.id = id
        self.createdAt = createdAt
        self.text = text
    }
}
