import Foundation

/// Contrato XPC entre o app e o helper privilegiado (ADR-4, v2).
///
/// **Superfície deliberadamente estreita.** O port `PrivilegeEscalating` do MVP recebe um comando
/// shell arbitrário; expor isso via XPC transformaria o helper num "root shell as a service" para
/// qualquer processo local. Aqui o helper só aceita uma lista de domínios — ele mesmo monta o bloco
/// do `/etc/hosts`, revalidando tudo (nunca confia no cliente).
@objc public protocol HostsHelperProtocol {
    /// Escreve o bloco do Tomafoco no `/etc/hosts` com os domínios informados.
    /// `errorMessage` é `nil` em caso de sucesso.
    func applyBlock(domains: [String], reply: @escaping (_ errorMessage: String?) -> Void)

    /// Remove o bloco do Tomafoco do `/etc/hosts`. No-op se não houver bloco.
    func removeBlock(reply: @escaping (_ errorMessage: String?) -> Void)

    /// Versão do helper instalado — permite ao app detectar helper defasado após update.
    func version(reply: @escaping (_ version: String) -> Void)
}

/// Identificadores compartilhados entre app e helper.
public enum HostsHelperInfo {
    /// Label do launchd, nome do Mach service e nome do plist em `Contents/Library/LaunchDaemons`.
    public static let machServiceName = "com.dsdumba.tomafoco.helper"
    public static let plistName = "com.dsdumba.tomafoco.helper.plist"
    /// Incrementar quando o contrato mudar — o app reinstala o helper se a versão divergir.
    public static let version = "1"

    /// Bundle ID do app; o helper só aceita conexões de um cliente que satisfaça este requisito.
    public static let clientBundleID = "com.dsdumba.tomafoco"
    public static let teamIdentifier = "CJQ7T4KV7H"

    /// Requisito de assinatura de código exigido do cliente que se conecta ao helper.
    public static var clientCodeRequirement: String {
        "identifier \"\(clientBundleID)\" and anchor apple generic "
            + "and certificate leaf[subject.OU] = \"\(teamIdentifier)\""
    }
}
