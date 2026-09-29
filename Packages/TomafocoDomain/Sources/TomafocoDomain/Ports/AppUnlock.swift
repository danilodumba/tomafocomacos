import Foundation

/// Senha de desbloqueio de apps (FEAT-002). Implementado por `KeychainAppUnlockPasswordStore`
/// na Infrastructure — o Domain só conhece o contrato; hash e Keychain ficam lá.
public protocol AppUnlockPasswordStoring: AnyObject, Sendable {
    /// Há senha cadastrada? Sem senha, app bloqueado é só encerrado (comportamento clássico).
    var hasPassword: Bool { get }
    /// Cadastra/substitui a senha. Lança `DomainError.weakPassword` se for curta demais.
    func setPassword(_ password: String) throws
    func verify(_ password: String) -> Bool
    func removePassword()
}

/// Regra de senha compartilhada entre store e UI.
public enum AppUnlockPasswordRule {
    public static let minimumLength = 4

    public static func validate(_ password: String) throws {
        guard password.count >= minimumLength else {
            throw DomainError.weakPassword(minimumLength: minimumLength)
        }
    }
}

/// Pede a senha ao usuário (FEAT-002). O verificador vem de fora: a UI nunca vê o hash,
/// só pergunta "está certa?" — e fica aberta até acertar ou o usuário cancelar.
public protocol AppUnlockPrompting: AnyObject {
    /// `true` quando o usuário digitou a senha certa; `false` ao cancelar.
    @MainActor
    func requestPassword(appName: String, verify: @escaping (String) -> Bool) async -> Bool
}
