import Foundation

/// Eventos que a Application pede para notificar ao usuário (RF-08). A tradução para
/// texto/localização e `UNUserNotificationCenter` fica na Infrastructure/Presentation.
public enum NotificationEvent: Equatable, Sendable {
    case focusEnded
    case shortBreakEnded
    case longBreakEnded
    case appBlocked(name: String)
    case websiteBlockingUnavailable
}
