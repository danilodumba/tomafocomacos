import Foundation

/// Erros da fronteira de elevação de privilégio (usado pelos adapters de Infrastructure).
/// Definido no Domain para que o fluxo alternativo 4a do UC-01 (usuário nega a senha)
/// possa ser tratado pela Application sem conhecer AppleScript/XPC.
public enum PrivilegeError: Error, Equatable {
    /// O usuário cancelou o prompt de senha de administrador.
    case userCancelled
    /// A operação privilegiada falhou por outro motivo (mensagem técnica para log).
    case executionFailed(String)
}
