import Foundation
import TomafocoDomain

/// Estado interno da máquina de sessões. Distinto de `SessionPhase`: aqui modelamos também
/// `paused` e carregamos a `PomodoroSession` corrente quando existe.
public enum SessionMachineState: Equatable {
    case idle
    case running(PomodoroSession)
    case paused(session: PomodoroSession, remaining: TimeInterval)
    /// Intervalo terminou e aguarda confirmação para o próximo foco (auto-início desligado).
    case awaitingNextFocus(nextCycle: Int)

    public var currentSession: PomodoroSession? {
        switch self {
        case .running(let s): return s
        case .paused(let s, _): return s
        case .idle, .awaitingNextFocus: return nil
        }
    }
}
