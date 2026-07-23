import Foundation
import TomafocoDomain

/// Eventos que dirigem a máquina de estados do Pomodoro.
public enum SessionEvent: Equatable {
    case startFocus(reason: String?, taskID: UUID?)
    case tick
    case pause
    case resume
    case cancel
    /// Usuário confirma o início da próxima etapa (quando o avanço automático está desligado).
    case beginNextPhase
    /// Readota uma sessão persistida após crash/reinício (UC-04): volta a valer de onde parou,
    /// com o mesmo `endsAt` absoluto — por isso o tempo perdido no crash não é devolvido.
    case adoptRecovered(PomodoroSession)
    /// Usuário pula a fase corrente (RF-04.2): foco → intervalo, intervalo → próximo foco.
    /// Pular um foco passa pela mesma trava de hardcore do cancelamento (validada no coordinator).
    case skipPhase
}
