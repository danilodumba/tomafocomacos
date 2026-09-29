import Foundation
import TomafocoDomain

/// Pede a senha do Tomafoco antes de uma ação que enfraquece o bloqueio (FEAT-002): desligar o
/// bloqueio contínuo, trocar ou remover a própria senha. Sem senha cadastrada, libera direto.
@MainActor
final class ProtectedActionAuthorizer {

    private let store: AppUnlockPasswordStoring
    private let presenter: AppUnlockPromptPresenter

    init(store: AppUnlockPasswordStoring, presenter: AppUnlockPromptPresenter) {
        self.store = store
        self.presenter = presenter
    }

    var hasPassword: Bool { store.hasPassword }

    func authorize(_ action: String) async -> Bool {
        guard store.hasPassword else { return true }
        let store = self.store
        return await presenter.request(
            title: "Confirme com a senha",
            message: "Digite a senha do Tomafoco para \(action).",
            confirmTitle: "Confirmar",
            verify: { store.verify($0) })
    }
}
