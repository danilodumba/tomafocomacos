import Foundation
import TomafocoDomain

/// ViewModel de configurações (RF-05.1). Edita a `PomodoroConfiguration` persistida.
///
/// Cada campo persiste no `didSet` — a janela de preferências do macOS não tem "OK/Cancelar",
/// então salvar só no fechamento perderia alterações se o app fosse encerrado antes.
@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var focusMinutes: Double { didSet { save() } }
    @Published var shortBreakMinutes: Double { didSet { save() } }
    @Published var longBreakMinutes: Double { didSet { save() } }
    @Published var cyclesBeforeLongBreak: Int { didSet { save() } }
    @Published var autoAdvancePhases: Bool { didSet { save() } }
    @Published var forceTerminateApps: Bool { didSet { save() } }
    /// Site para onde a aba bloqueada é redirecionada. Vazio → página de bloqueio padrão.
    @Published var blockedRedirectURL: String { didSet { save() } }
    /// Espelha conclusão/reabertura de tarefas importadas de volta no app Lembretes.
    @Published var syncReminderCompletion: Bool { didSet { save() } }
    /// Permite selecionar mais de uma tarefa por sessão de foco (RF-09.4).
    @Published var allowMultipleTasksInFocus: Bool { didSet { save() } }
    /// Bloqueio contínuo com o Tomafoco aberto (FEAT-002). Só mudam via `setBlock…` — desligar
    /// exige senha, então o `Toggle` não escreve direto aqui.
    @Published private(set) var blockAppsWhileRunning: Bool
    @Published private(set) var blockSitesWhileRunning: Bool

    /// Iniciar junto com o macOS (item de login). NÃO vive na `PomodoroConfiguration`:
    /// a fonte da verdade é o sistema (`SMAppService`), que o usuário pode mudar por fora.
    @Published var launchAtLogin: Bool { didSet { applyLaunchAtLogin(oldValue) } }
    @Published var launchAtLoginError: String?
    /// Suprime o `didSet` quando o valor vem DO sistema (refresh/reversão) — sem isso,
    /// reverter após falha chamaria `setEnabled` de novo, em loop.
    private var isSyncingLoginItem = false

    private let settings: SettingsRepository
    private let loginItem: LoginItemManaging
    private let authorizer: ProtectedActionAuthorizer
    /// Reaplica o bloqueio fora do foco quando uma flag muda.
    private let onBlockingSettingsChanged: () -> Void

    init(
        settings: SettingsRepository,
        loginItem: LoginItemManaging,
        authorizer: ProtectedActionAuthorizer,
        onBlockingSettingsChanged: @escaping () -> Void
    ) {
        self.settings = settings
        self.loginItem = loginItem
        self.authorizer = authorizer
        self.onBlockingSettingsChanged = onBlockingSettingsChanged
        // Observadores de propriedade não disparam durante a init — nenhum save espúrio aqui.
        let config = settings.loadConfiguration()
        focusMinutes = config.focusDuration / 60
        shortBreakMinutes = config.shortBreakDuration / 60
        longBreakMinutes = config.longBreakDuration / 60
        cyclesBeforeLongBreak = config.cyclesBeforeLongBreak
        autoAdvancePhases = config.autoAdvancePhases
        forceTerminateApps = config.forceTerminateApps
        blockedRedirectURL = config.blockedRedirectURL ?? ""
        syncReminderCompletion = config.syncReminderCompletion
        allowMultipleTasksInFocus = config.allowMultipleTasksInFocus
        blockAppsWhileRunning = config.blockAppsWhileRunning
        blockSitesWhileRunning = config.blockSitesWhileRunning
        launchAtLogin = loginItem.isEnabled
    }

    /// Relê o estado do sistema — chamado quando a janela aparece, porque o usuário pode
    /// ter removido o item de login pelos Ajustes do Sistema.
    func refreshLaunchAtLogin() {
        isSyncingLoginItem = true
        launchAtLogin = loginItem.isEnabled
        isSyncingLoginItem = false
    }

    private func applyLaunchAtLogin(_ oldValue: Bool) {
        guard !isSyncingLoginItem, launchAtLogin != oldValue else { return }
        do {
            try loginItem.setEnabled(launchAtLogin)
            launchAtLoginError = nil
        } catch {
            isSyncingLoginItem = true
            launchAtLogin = oldValue
            isSyncingLoginItem = false
            launchAtLoginError = "Não foi possível alterar o item de login: \(error.localizedDescription)"
        }
    }

    func setBlockAppsWhileRunning(_ enabled: Bool) async {
        guard enabled != blockAppsWhileRunning else { return }
        if !enabled, !(await authorizer.authorize("desligar o bloqueio contínuo de apps")) { return }
        blockAppsWhileRunning = enabled
        save()
        onBlockingSettingsChanged()
    }

    func setBlockSitesWhileRunning(_ enabled: Bool) async {
        guard enabled != blockSitesWhileRunning else { return }
        if !enabled, !(await authorizer.authorize("desligar o bloqueio contínuo de sites")) { return }
        blockSitesWhileRunning = enabled
        save()
        onBlockingSettingsChanged()
    }

    /// Persiste a configuração atual.
    func save() {
        let config = PomodoroConfiguration(
            focusDuration: focusMinutes * 60,
            shortBreakDuration: shortBreakMinutes * 60,
            longBreakDuration: longBreakMinutes * 60,
            cyclesBeforeLongBreak: cyclesBeforeLongBreak,
            autoAdvancePhases: autoAdvancePhases,
            forceTerminateApps: forceTerminateApps,
            // Vazio vira nil: o blocker interpreta nil como "página padrão".
            blockedRedirectURL: blockedRedirectURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nil : blockedRedirectURL.trimmingCharacters(in: .whitespacesAndNewlines),
            syncReminderCompletion: syncReminderCompletion,
            allowMultipleTasksInFocus: allowMultipleTasksInFocus,
            blockAppsWhileRunning: blockAppsWhileRunning,
            blockSitesWhileRunning: blockSitesWhileRunning
        )
        settings.save(config)
    }
}
