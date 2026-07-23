import Foundation

/// Sessão Pomodoro em andamento.
/// Guarda `endsAt` (horário absoluto) em vez de contador decremental para sobreviver a
/// crash/sleep/reboot (RF-01.5, ADR-6).
public struct PomodoroSession: Equatable, Codable, Sendable, Identifiable {
    public let id: UUID
    public let phase: SessionPhase
    public let startedAt: Date
    public let endsAt: Date
    public let reason: String?
    public let cycleNumber: Int
    /// Tarefa em foco (RF-09). Opcional: snapshot antigo sem a chave decodifica `nil`.
    public let taskID: UUID?

    public init(
        id: UUID,
        phase: SessionPhase,
        startedAt: Date,
        endsAt: Date,
        reason: String?,
        cycleNumber: Int,
        taskID: UUID?
    ) {
        self.id = id
        self.phase = phase
        self.startedAt = startedAt
        self.endsAt = endsAt
        self.reason = reason
        self.cycleNumber = cycleNumber
        self.taskID = taskID
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
}
