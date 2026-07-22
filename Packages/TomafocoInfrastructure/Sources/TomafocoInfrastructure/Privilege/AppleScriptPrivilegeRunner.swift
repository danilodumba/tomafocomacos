import Foundation
import OSLog
import TomafocoDomain

#if os(macOS)

/// Elevação de privilégio via AppleScript `with administrator privileges` (MVP, ADR-4).
/// O prompt de senha é do próprio macOS — o app nunca vê a senha (RNF-04).
///
/// v2: substituir por um `XPCHelperPrivilegeRunner` (SMAppService.daemon). Como ambos implementam
/// `PrivilegeEscalating`, a troca é feita só no Composition Root (OCP).
public final class AppleScriptPrivilegeRunner: PrivilegeEscalating, @unchecked Sendable {

    /// Diagnóstico do que roda como root. Ver com:
    /// `log show --last 10m --predicate 'subsystem == "com.dsdumba.tomafoco"'`
    /// Marcado como público porque o comando não carrega segredo — só caminhos e utilitários.
    private static let log = Logger(subsystem: "com.dsdumba.tomafoco", category: "privilege")

    public init() {}

    public func runPrivileged(command: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            // NSAppleScript deve rodar na main thread.
            DispatchQueue.main.async {
                let escaped = command
                    .replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "\"", with: "\\\"")
                let source = "do shell script \"\(escaped)\" with administrator privileges"

                Self.log.info("elevando privilégio: \(command, privacy: .public)")

                var errorInfo: NSDictionary?
                guard let script = NSAppleScript(source: source) else {
                    continuation.resume(throwing: PrivilegeError.executionFailed("script inválido"))
                    return
                }
                script.executeAndReturnError(&errorInfo)

                if let errorInfo {
                    // Chaves padrão do dicionário de erro do NSAppleScript.
                    let code = (errorInfo["NSAppleScriptErrorNumber"] as? Int) ?? 0
                    // -128 = usuário cancelou o prompt de autenticação.
                    if code == -128 {
                        Self.log.notice("usuário cancelou o prompt de administrador")
                        continuation.resume(throwing: PrivilegeError.userCancelled)
                    } else {
                        let msg = (errorInfo["NSAppleScriptErrorMessage"] as? String) ?? "erro \(code)"
                        Self.log.error("comando privilegiado falhou (\(code)): \(msg, privacy: .public)")
                        continuation.resume(throwing: PrivilegeError.executionFailed(msg))
                    }
                } else {
                    Self.log.info("comando privilegiado concluído")
                    continuation.resume(returning: ())
                }
            }
        }
    }
}
#endif
