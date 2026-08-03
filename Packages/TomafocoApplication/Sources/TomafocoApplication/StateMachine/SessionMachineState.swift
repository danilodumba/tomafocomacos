import Foundation
import TomafocoDomain

/// Estado interno da máquina de sessões. Distinto de `SessionPhase`: aqui modelamos também
/// `paused` e carregamos a `PomodoroSession` corrente quando existe.
public enum SessionMachineState: Equatable {
    case idle
    case running(PomodoroSession)
    case paused(session: PomodoroSession, remaining: TimeInterval)
    /// Uma etapa terminou e o app aguarda confirmação para iniciar a próxima
    /// (avanço automático desligado). Vale tanto para foco → intervalo quanto intervalo → foco.
    /// Carrega os `taskIDs` para as tarefas atravessarem o ciclo inteiro (RF-09).
    case awaitingNext(phase: SessionPhase, cycle: Int, taskIDs: [UUID])

    public var currentSession: PomodoroSession? {
        switch self {
        case .running(let s): return s
        case .paused(let s, _): return s
        case .idle, .awaitingNext: return nil
        }
    }
}
