import Foundation

/// Bloqueio de aplicativos (RF-03). Implementado por `WorkspaceAppBlocker` na Infrastructure.
public protocol AppBlocking: AnyObject, Sendable {
    /// Encerra os apps já em execução e passa a observar novos lançamentos.
    func activate(blockedBundleIDs: Set<String>)
    /// Remove o observer e libera os apps.
    func deactivate()
}

/// Bloqueio de sites (RF-02). Implementado por `AppleScriptBrowserBlocker` na Infrastructure (ADR-8).
///
/// Contrato de idempotência (RNF-01):
/// - `activate` chamado 2x não duplica efeito (só atualiza a lista vigente).
/// - `deactivate` sem bloqueio ativo é no-op.
/// - após um ciclo activate→deactivate, o sistema volta ao estado anterior — nenhum
///   resíduo de bloqueio pode sobreviver ao fim da sessão (RNF-02).
public protocol WebsiteBlocking: AnyObject, Sendable {
    func activate(domains: [BlockedDomain]) async throws
    func deactivate() async throws
    var isActive: Bool { get async }
}
