import Foundation

/// Bloqueio de aplicativos (RF-03). Implementado por `WorkspaceAppBlocker` na Infrastructure.
public protocol AppBlocking: AnyObject, Sendable {
    /// Encerra os apps já em execução e passa a observar novos lançamentos.
    func activate(blockedBundleIDs: Set<String>)
    /// Remove o observer e libera os apps.
    func deactivate()
}

/// Bloqueio de sites (RF-02). Implementado por `HostsFileWebsiteBlocker` na Infrastructure.
///
/// Contrato de idempotência (RNF-01):
/// - `activate` chamado 2x não duplica entradas.
/// - `deactivate` sem bloco presente é no-op.
/// - após um ciclo activate→deactivate, o arquivo hosts volta ao estado original.
public protocol WebsiteBlocking: AnyObject, Sendable {
    func activate(domains: [BlockedDomain]) async throws
    func deactivate() async throws
    var isActive: Bool { get async }
}

/// Elevação de privilégio para operações que exigem root (editar `/etc/hosts`).
/// MVP: AppleScript admin. v2: XPC helper — trocável por injeção (OCP/ADR-4).
public protocol PrivilegeEscalating: Sendable {
    /// Executa um comando shell com privilégio de administrador.
    /// Lança `PrivilegeError.userCancelled` se o usuário cancelar o prompt.
    func runPrivileged(command: String) async throws
}
