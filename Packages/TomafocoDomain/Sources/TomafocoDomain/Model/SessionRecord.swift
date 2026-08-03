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
    /// Tarefas vinculadas (RF-09). Histórico antigo com a chave singular `taskID` decodifica para
    /// `[uuid]`; sem qualquer chave → `[]` → "Sem tarefa" no relatório.
    public let taskIDs: [UUID]

    public init(
        sessionID: UUID,
        phase: SessionPhase,
        startedAt: Date,
        endedAt: Date,
        outcome: Outcome,
        cycleNumber: Int,
        taskIDs: [UUID]
    ) {
        self.sessionID = sessionID
        self.phase = phase
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.outcome = outcome
        self.cycleNumber = cycleNumber
        self.taskIDs = taskIDs
    }

    // Codable manual só pela migração `taskID` (singular) → `taskIDs` (plural) — mesma de
    // `PomodoroSession`. Reusa `PomodoroSession.decodeTaskIDs`. `encode` grava só a chave nova.
    private enum CodingKeys: String, CodingKey {
        case sessionID, phase, startedAt, endedAt, outcome, cycleNumber
        case taskIDs
        case legacyTaskID = "taskID"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.sessionID = try c.decode(UUID.self, forKey: .sessionID)
        self.phase = try c.decode(SessionPhase.self, forKey: .phase)
        self.startedAt = try c.decode(Date.self, forKey: .startedAt)
        self.endedAt = try c.decode(Date.self, forKey: .endedAt)
        self.outcome = try c.decode(Outcome.self, forKey: .outcome)
        self.cycleNumber = try c.decode(Int.self, forKey: .cycleNumber)
        self.taskIDs = try PomodoroSession.decodeTaskIDs(from: c, plural: .taskIDs, legacy: .legacyTaskID)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(sessionID, forKey: .sessionID)
        try c.encode(phase, forKey: .phase)
        try c.encode(startedAt, forKey: .startedAt)
        try c.encode(endedAt, forKey: .endedAt)
        try c.encode(outcome, forKey: .outcome)
        try c.encode(cycleNumber, forKey: .cycleNumber)
        try c.encode(taskIDs, forKey: .taskIDs)
    }
}
