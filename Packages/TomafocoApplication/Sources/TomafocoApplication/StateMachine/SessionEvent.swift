import Foundation
import TomafocoDomain

/// Eventos que dirigem a máquina de estados do Pomodoro.
public enum SessionEvent: Equatable {
    case startFocus(taskIDs: [UUID])
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
    case skipPhase
    /// Troca as tarefas vinculadas à sessão corrente (RF-09.1). Só vale com o foco pausado:
    /// o usuário finalizou/mudou de tarefa no meio do foco. `[]` = passar a focar sem tarefa.
    case changeTask(taskIDs: [UUID])
}
