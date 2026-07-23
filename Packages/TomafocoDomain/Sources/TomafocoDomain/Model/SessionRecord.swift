import Foundation

/// Registro histórico de uma sessão encerrada (RF-07.1). Persistido pelo `SessionRepository`.
public struct SessionRecord: Equatable, Codable, Sendable {
    public enum Outcome: String, Equatable, Codable, Sendable {
        case completed
        case cancelled
        case recovered  // encerrada pelo failsafe após crash (UC-04)
        case skipped    // intervalo pulado pelo usuário (RF-04.2)
    }

    public let sessionID: UUID
    public let phase: SessionPhase
    public let startedAt: Date
    public let endedAt: Date
    public let outcome: Outcome
    public let cycleNumber: Int
    /// Tarefa vinculada (RF-09). Histórico antigo sem a chave decodifica `nil` → "Sem tarefa".
    public let taskID: UUID?

    public init(
        sessionID: UUID,
        phase: SessionPhase,
        startedAt: Date,
        endedAt: Date,
        outcome: Outcome,
        cycleNumber: Int,
        taskID: UUID?
    ) {
        self.sessionID = sessionID
        self.phase = phase
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.outcome = outcome
        self.cycleNumber = cycleNumber
        self.taskID = taskID
    }
}
