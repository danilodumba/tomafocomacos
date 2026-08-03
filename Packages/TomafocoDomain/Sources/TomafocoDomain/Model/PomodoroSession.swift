import Foundation

/// Sessão Pomodoro em andamento.
/// Guarda `endsAt` (horário absoluto) em vez de contador decremental para sobreviver a
/// crash/sleep/reboot (RF-01.5, ADR-6).
public struct PomodoroSession: Equatable, Codable, Sendable, Identifiable {
    public let id: UUID
    public let phase: SessionPhase
    public let startedAt: Date
    public let endsAt: Date
    public let cycleNumber: Int
    /// Tarefas em foco (RF-09). Pode ter 0, 1 ou N quando o foco multi-tarefa está ligado.
    /// Snapshot antigo com a chave singular `taskID` decodifica para `[uuid]` (ou `[]` se nulo).
    public let taskIDs: [UUID]

    public init(
        id: UUID,
        phase: SessionPhase,
        startedAt: Date,
        endsAt: Date,
        cycleNumber: Int,
        taskIDs: [UUID]
    ) {
        self.id = id
        self.phase = phase
        self.startedAt = startedAt
        self.endsAt = endsAt
        self.cycleNumber = cycleNumber
        self.taskIDs = taskIDs
    }

    // Codable manual só por causa da migração `taskID` (singular) → `taskIDs` (plural): snapshots
    // gravados antes do foco multi-tarefa têm a chave antiga. `encode` grava só a chave nova.
    private enum CodingKeys: String, CodingKey {
        case id, phase, startedAt, endsAt, cycleNumber
        case taskIDs
        case legacyTaskID = "taskID"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.phase = try c.decode(SessionPhase.self, forKey: .phase)
        self.startedAt = try c.decode(Date.self, forKey: .startedAt)
        self.endsAt = try c.decode(Date.self, forKey: .endsAt)
        self.cycleNumber = try c.decode(Int.self, forKey: .cycleNumber)
        self.taskIDs = try PomodoroSession.decodeTaskIDs(from: c, plural: .taskIDs, legacy: .legacyTaskID)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(phase, forKey: .phase)
        try c.encode(startedAt, forKey: .startedAt)
        try c.encode(endsAt, forKey: .endsAt)
        try c.encode(cycleNumber, forKey: .cycleNumber)
        try c.encode(taskIDs, forKey: .taskIDs)
    }

    /// Decodifica `taskIDs` tolerando o formato antigo de chave única `taskID`. Compartilhado com
    /// `SessionRecord`, que fez a mesma migração.
    static func decodeTaskIDs<K: CodingKey>(
        from container: KeyedDecodingContainer<K>, plural: K, legacy: K
    ) throws -> [UUID] {
        if let ids = try container.decodeIfPresent([UUID].self, forKey: plural) {
            return ids
        }
        if let single = try container.decodeIfPresent(UUID.self, forKey: legacy) {
            return [single]
        }
        return []
    }

    /// Tempo restante (nunca negativo) relativo a um instante `now` injetado — nunca use `Date()` aqui.
    public func remaining(now: Date) -> TimeInterval {
        max(0, endsAt.timeIntervalSince(now))
    }

    /// A sessão já deveria ter terminado? Base para o failsafe (UC-04).
    public func isExpired(now: Date) -> Bool {
        now >= endsAt
    }

    /// Duração total planejada da sessão.
    public var plannedDuration: TimeInterval {
        endsAt.timeIntervalSince(startedAt)
    }

    /// Cópia com outras tarefas vinculadas. Todos os campos são `let`, então trocar as tarefas
    /// (RF-09.1 — finalizar/trocar tarefa no meio do foco) exige reconstruir a struct.
    public func with(taskIDs: [UUID]) -> PomodoroSession {
        PomodoroSession(
            id: id, phase: phase, startedAt: startedAt, endsAt: endsAt,
            cycleNumber: cycleNumber, taskIDs: taskIDs
        )
    }
}
