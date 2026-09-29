import Foundation
import TomafocoDomain

/// Cadastro da senha de desbloqueio de apps (FEAT-002). Separado do `SettingsViewModel` porque
/// a senha não vive na `PomodoroConfiguration` — vive (como hash) no Keychain.
@MainActor
final class UnlockPasswordViewModel: ObservableObject {
    @Published private(set) var hasPassword: Bool
    @Published var newPassword = ""
    @Published var confirmation = ""
    @Published private(set) var errorMessage: String?
    @Published private(set) var infoMessage: String?

    private let store: AppUnlockPasswordStoring
    private let authorizer: ProtectedActionAuthorizer

    init(store: AppUnlockPasswordStoring, authorizer: ProtectedActionAuthorizer) {
        self.store = store
        self.authorizer = authorizer
        self.hasPassword = store.hasPassword
    }

    var canSave: Bool { !newPassword.isEmpty && !confirmation.isEmpty }

    /// Define ou troca a senha. Trocar exige a senha atual — senão ela não protegeria nada.
    func save() async {
        errorMessage = nil
        infoMessage = nil
        guard newPassword == confirmation else {
            errorMessage = "As senhas não conferem."
            return
        }
        do {
            try AppUnlockPasswordRule.validate(newPassword)
        } catch {
            errorMessage = "A senha precisa ter pelo menos \(AppUnlockPasswordRule.minimumLength) caracteres."
            return
        }
        guard await authorizer.authorize("trocar a senha") else { return }
        do {
            let hadPassword = store.hasPassword
            try store.setPassword(newPassword)
            newPassword = ""
            confirmation = ""
            hasPassword = true
            infoMessage = hadPassword ? "Senha alterada." : "Senha definida."
        } catch {
            errorMessage = "Não foi possível salvar a senha: \(error.localizedDescription)"
        }
    }

    func remove() async {
        errorMessage = nil
        infoMessage = nil
        guard await authorizer.authorize("remover a senha") else { return }
        store.removePassword()
        hasPassword = false
        infoMessage = "Senha removida. Apps bloqueados voltam a ser só encerrados."
    }
}
