import Foundation
import TomafocoDomain

/// Efeitos colaterais que a máquina de estados PEDE, mas não executa (SRP).
/// Quem interpreta é o `SessionCoordinator`, mantendo a transição pura e testável.
public enum SessionEffect: Equatable {
    case activateBlocking
    case deactivateBlocking
    case persistActive(PomodoroSession)
    case clearActive
    case recordHistory(SessionRecord)
    case notify(NotificationEvent)
}
