import Foundation
import TomafocoDomain

#if canImport(UserNotifications)
import UserNotifications

/// `UserNotifying` sobre `UNUserNotificationCenter` (RF-08). Degrada graciosamente se a permissão
/// for negada (RF-08.2): nunca lança, apenas não exibe. As strings ficam aqui (Presentation-layer
/// de texto), nunca no domínio.
public final class UNNotificationAdapter: UserNotifying, @unchecked Sendable {

    private let center: UNUserNotificationCenter
    /// Retido aqui: `UNUserNotificationCenter.delegate` é `weak` e o delegate seria liberado
    /// na hora, deixando as notificações invisíveis com o app em primeiro plano.
    private let presenter = ForegroundPresenter()

    public init(center: UNUserNotificationCenter = .current()) {
        self.center = center
        center.delegate = presenter
    }

    /// Solicita autorização no primeiro uso. Chamar no onboarding.
    public func requestAuthorization() {
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    public func notify(_ event: NotificationEvent) {
        let content = UNMutableNotificationContent()
        content.sound = .default
        switch event {
        case .focusEnded:
            content.title = "Foco concluído"
            content.body = "Hora do intervalo. Os bloqueios foram liberados."
        case .shortBreakEnded:
            content.title = "Intervalo terminado"
            content.body = "Pronto para o próximo foco?"
        case .longBreakEnded:
            content.title = "Intervalo longo terminado"
            content.body = "Pronto para retomar o foco?"
        case .appBlocked(let name):
            content.title = "App bloqueado"
            content.body = "\(name) foi encerrado durante o foco."
        case .websiteBlockingUnavailable:
            content.title = "Bloqueio de sites indisponível"
            content.body = "A sessão continua com o bloqueio de apps apenas."
        }

        let request = UNNotificationRequest(
            identifier: UUID().uuidString, content: content, trigger: nil)
        center.add(request, withCompletionHandler: nil)
    }
}

/// Sem delegate, o macOS **esconde** a notificação quando o app está em primeiro plano.
/// Como o Tomafoco costuma estar aberto justamente quando a etapa termina, esse é o caso
/// comum — sem isso o usuário simplesmente não veria o aviso de fim de foco.
private final class ForegroundPresenter: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }
}
#endif
