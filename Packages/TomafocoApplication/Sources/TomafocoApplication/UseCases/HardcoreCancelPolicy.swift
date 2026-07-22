import Foundation
import TomafocoDomain

/// Política pura que decide se um cancelamento pode ocorrer no modo hardcore (RF-06.1, UC-03).
/// Separada da máquina de estados (SRP) e testável isoladamente.
public enum HardcoreCancelPolicy {

    /// Verifica se a sessão de foco pode ser cancelada agora.
    /// - Retorna `.success` quando permitido; caso contrário `DomainError.cancellationBlockedByHardcore`.
    public static func validate(
        session: PomodoroSession,
        config: PomodoroConfiguration,
        now: Date
    ) -> Result<Void, DomainError> {
        guard config.hardcore.isEnabled, session.phase == .focus else { return .success(()) }

        let elapsed = now.timeIntervalSince(session.startedAt)
        let graceSeconds = TimeInterval(config.hardcore.minimumMinutesBeforeCancel * 60)
        guard elapsed >= graceSeconds else {
            let remaining = Int((graceSeconds - elapsed).rounded(.up))
            return .failure(.cancellationBlockedByHardcore(remainingSeconds: remaining))
        }
        return .success(())
    }
}
