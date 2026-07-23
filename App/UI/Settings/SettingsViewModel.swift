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
    @Published var hardcoreEnabled: Bool { didSet { save() } }
    @Published var hardcoreGraceMinutes: Int { didSet { save() } }
    @Published var hardcoreRequireReason: Bool { didSet { save() } }
    /// Site para onde a aba bloqueada é redirecionada. Vazio → página de bloqueio padrão.
    @Published var blockedRedirectURL: String { didSet { save() } }
    /// Espelha conclusão/reabertura de tarefas importadas de volta no app Lembretes.
    @Published var syncReminderCompletion: Bool { didSet { save() } }

    /// Iniciar junto com o macOS (item de login). NÃO vive na `PomodoroConfiguration`:
    /// a fonte da verdade é o sistema (`SMAppService`), que o usuário pode mudar por fora.
    @Published var launchAtLogin: Bool { didSet { applyLaunchAtLogin(oldValue) } }
    @Published var launchAtLoginError: String?
    /// Suprime o `didSet` quando o valor vem DO sistema (refresh/reversão) — sem isso,
    /// reverter após falha chamaria `setEnabled` de novo, em loop.
    private var isSyncingLoginItem = false

    private let settings: SettingsRepository
    private let loginItem: LoginItemManaging

    init(settings: SettingsRepository, loginItem: LoginItemManaging) {
        self.settings = settings
        self.loginItem = loginItem
        // Observadores de propriedade não disparam durante a init — nenhum save espúrio aqui.
        let config = settings.loadConfiguration()
        focusMinutes = config.focusDuration / 60
        shortBreakMinutes = config.shortBreakDuration / 60
        longBreakMinutes = config.longBreakDuration / 60
        cyclesBeforeLongBreak = config.cyclesBeforeLongBreak
        autoAdvancePhases = config.autoAdvancePhases
        forceTerminateApps = config.forceTerminateApps
        hardcoreEnabled = config.hardcore.isEnabled
        hardcoreGraceMinutes = config.hardcore.minimumMinutesBeforeCancel
        hardcoreRequireReason = config.hardcore.requireReason
        blockedRedirectURL = config.blockedRedirectURL ?? ""
        syncReminderCompletion = config.syncReminderCompletion
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

    /// Persiste a configuração atual.
    func save() {
        let config = PomodoroConfiguration(
            focusDuration: focusMinutes * 60,
            shortBreakDuration: shortBreakMinutes * 60,
            longBreakDuration: longBreakMinutes * 60,
            cyclesBeforeLongBreak: cyclesBeforeLongBreak,
            autoAdvancePhases: autoAdvancePhases,
            forceTerminateApps: forceTerminateApps,
            hardcore: HardcoreOptions(
                isEnabled: hardcoreEnabled,
                minimumMinutesBeforeCancel: hardcoreGraceMinutes,
                requireReason: hardcoreRequireReason
            ),
            // Vazio vira nil: o blocker interpreta nil como "página padrão".
            blockedRedirectURL: blockedRedirectURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nil : blockedRedirectURL.trimmingCharacters(in: .whitespacesAndNewlines),
            syncReminderCompletion: syncReminderCompletion
        )
        settings.save(config)
    }
}
