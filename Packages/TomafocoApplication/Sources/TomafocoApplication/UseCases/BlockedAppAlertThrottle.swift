import Foundation

/// Evita repetir o aviso de app bloqueado a cada tentativa (RF-03, RF-08).
///
/// Quem insiste em abrir um app bloqueado costuma clicar várias vezes seguidas — e alguns apps
/// (Slack, Teams) relançam sozinhos ao serem encerrados. Sem represa, a tela viraria uma
/// sequência de avisos idênticos e o usuário passaria a ignorá-los.
///
/// A represa é **por app**: um app em loop não pode calar o aviso de outro que o usuário
/// abriu de propósito.
public struct BlockedAppAlertThrottle {

    private let cooldown: TimeInterval
    private var lastShown: [String: Date] = [:]

    public init(cooldown: TimeInterval = 5) {
        self.cooldown = cooldown
    }

    /// Deve exibir o aviso agora? Registra a exibição quando responde `true`.
    public mutating func shouldPresent(app: String, now: Date) -> Bool {
        if let last = lastShown[app], now.timeIntervalSince(last) < cooldown {
            return false
        }
        lastShown[app] = now
        return true
    }

    /// Zera a memória — chamar ao encerrar a sessão para que o próximo foco avise de novo.
    public mutating func reset() {
        lastShown.removeAll()
    }
}
