import Foundation
import TomafocoDomain

/// Emite um som audível. Port para testar o alerta sem tocar nada de verdade.
public protocol SoundPlaying: Sendable {
    func playAlert()
}

/// Pede a atenção do usuário quando o app não está em primeiro plano (ícone no Dock pulando).
public protocol AttentionRequesting: Sendable {
    func requestAttention()
}

/// Decora um `UserNotifying` acrescentando **som + alerta** no fim de cada etapa (RF-08.1).
///
/// Existe como decorador em vez de virar mais responsabilidade do `UNNotificationAdapter`
/// porque o som precisa tocar mesmo quando a permissão de notificação foi negada — se
/// dependesse do `UNUserNotificationCenter`, o usuário que recusou notificações ficaria sem
/// nenhum aviso de que o foco acabou.
public final class PhaseAlertNotifier: UserNotifying, @unchecked Sendable {

    private let wrapped: UserNotifying
    private let sound: SoundPlaying
    private let attention: AttentionRequesting

    public init(wrapping wrapped: UserNotifying, sound: SoundPlaying, attention: AttentionRequesting) {
        self.wrapped = wrapped
        self.sound = sound
        self.attention = attention
    }

    public func notify(_ event: NotificationEvent) {
        if Self.isPhaseEnd(event) {
            sound.playAlert()
            attention.requestAttention()
        }
        wrapped.notify(event)
    }

    /// Só o fim de etapa merece som. App bloqueado acontece várias vezes seguidas (o usuário
    /// insiste em abrir o app) e bloqueio indisponível é um aviso, não um marco do ciclo —
    /// tocar em todos viraria ruído e o usuário passaria a ignorar o alerta que importa.
    static func isPhaseEnd(_ event: NotificationEvent) -> Bool {
        switch event {
        case .focusEnded, .shortBreakEnded, .longBreakEnded:
            return true
        case .appBlocked, .websiteBlockingUnavailable:
            return false
        }
    }
}

#if canImport(AppKit)
import AppKit

/// Som de alerta do sistema. Usa o som escolhido pelo usuário nas Preferências do macOS,
/// respeitando o volume de alerta — não é um beep próprio ignorando as configurações dele.
public struct SystemSoundPlayer: SoundPlaying {

    private let soundName: String

    /// "Glass" é o som padrão; qualquer nome de `/System/Library/Sounds` serve.
    public init(soundName: String = "Glass") {
        self.soundName = soundName
    }

    public func playAlert() {
        if let sound = NSSound(named: soundName) {
            sound.play()
        } else {
            NSSound.beep()   // nome inválido não pode significar "sem aviso nenhum"
        }
    }
}

/// Faz o ícone do Dock pular até o usuário olhar. `.informationalRequest` pula uma vez;
/// `.criticalRequest` insiste — o fim de uma etapa merece insistência, é o ponto do app.
public struct DockAttentionRequester: AttentionRequesting {

    public init() {}

    public func requestAttention() {
        DispatchQueue.main.async {
            NSApp.requestUserAttention(.criticalRequest)
        }
    }
}
#endif
