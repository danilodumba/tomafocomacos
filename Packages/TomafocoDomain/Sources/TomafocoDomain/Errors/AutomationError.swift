import Foundation

/// Erros da fronteira de automação do navegador (ADR-8).
/// Definido no Domain para que a Application distinga "o usuário não autorizou" de
/// "falhou por outro motivo" sem conhecer AppleScript.
public enum AutomationError: Error, Equatable {
    /// O usuário não concedeu permissão de automação para o aplicativo alvo.
    /// Corresponde ao erro -1743 do AppleScript ("Not authorized to send Apple events").
    case permissionDenied(application: String)
    /// A automação falhou por outro motivo (mensagem técnica para log).
    case executionFailed(String)
}
