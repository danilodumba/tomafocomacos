import Foundation
import TomafocoDomain
import TomafocoApplication

/// ViewModel das listas de bloqueio de sites e apps (RF-05.2, UC-05).
@MainActor
final class BlockListViewModel: ObservableObject {
    @Published private(set) var domains: [BlockedDomain] = []
    @Published private(set) var apps: [BlockedApp] = []
    @Published var newDomain = ""
    @Published var errorMessage: String?

    /// `true` enquanto o seletor de apps está aberto — desabilita o botão para evitar 2 painéis.
    @Published private(set) var isPickingApps = false

    private let useCase: ManageBlockListUseCase
    private let appPicker: ApplicationPicking
    /// Reaplica o bloqueio contínuo (FEAT-002) — fora do foco a lista nova vale na hora.
    private let onListChanged: () -> Void

    init(useCase: ManageBlockListUseCase, appPicker: ApplicationPicking,
         onListChanged: @escaping () -> Void = {}) {
        self.useCase = useCase
        self.appPicker = appPicker
        self.onListChanged = onListChanged
        reload()
    }

    func reload() {
        let list = useCase.currentList()
        domains = list.domains
        apps = list.apps
    }

    func addDomain() {
        errorMessage = nil
        do {
            let list = try useCase.addDomain(raw: newDomain)
            domains = list.domains
            newDomain = ""
            onListChanged()
        } catch DomainError.invalidDomain(let raw) {
            errorMessage = "Domínio inválido: \(raw)"
        } catch DomainError.duplicateEntry {
            errorMessage = "Esse domínio já está na lista."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func removeDomain(_ domain: BlockedDomain) {
        domains = useCase.removeDomain(domain).domains
        onListChanged()
    }

    /// Abre o seletor de apps (`NSOpenPanel` em `/Applications`) e adiciona os escolhidos (T-20, UC-05).
    func addAppsFromPicker() async {
        guard !isPickingApps else { return }
        isPickingApps = true
        defer { isPickingApps = false }

        errorMessage = nil
        let picked = await appPicker.pickApplications()
        guard !picked.isEmpty else { return } // usuário cancelou

        let result = useCase.addApps(picked.apps)
        apps = result.list.apps
        errorMessage = Self.message(for: result, unreadableNames: picked.unreadableNames)
        onListChanged()
    }

    /// Adiciona apps arrastados para a lista (drag-and-drop de `.app`, T-20).
    func addApps(fromDroppedURLs urls: [URL]) {
        errorMessage = nil
        let picked = appPicker.applications(at: urls)
        guard !picked.isEmpty else { return }

        let result = useCase.addApps(picked.apps)
        apps = result.list.apps
        errorMessage = Self.message(for: result, unreadableNames: picked.unreadableNames)
        onListChanged()
    }

    /// Monta o aviso das seleções que não entraram na lista. `nil` quando tudo foi adicionado.
    static func message(for result: AddAppsResult, unreadableNames: [String]) -> String? {
        var parts: [String] = []
        if !result.duplicateNames.isEmpty {
            parts.append("Já estavam na lista: \(result.duplicateNames.joined(separator: ", ")).")
        }
        if !unreadableNames.isEmpty {
            parts.append("Sem bundle ID legível: \(unreadableNames.joined(separator: ", ")).")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    func removeApp(_ app: BlockedApp) {
        apps = useCase.removeApp(bundleID: app.bundleID).apps
        onListChanged()
    }

    func setApp(_ app: BlockedApp, enabled: Bool) {
        apps = useCase.setApp(bundleID: app.bundleID, enabled: enabled).apps
        onListChanged()
    }
}
