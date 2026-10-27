import Foundation
import TomafocoDomain
import TomafocoApplication

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
    /// Quais tarefas entram no seletor do foco (RF-09.15) — mesmo modelo do escopo do Kanban.
    /// Só muda via `setFocusScope…`, que grava e avisa o timer.
    @Published private(set) var focusTaskScope: TaskScope
    /// Tags conhecidas (tarefas + catálogo), relidas ao abrir a aba e quando as tarefas mudam.
    @Published private(set) var knownTags: [String] = []

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
    private let manageTasks: ManageTasksUseCase
    /// Reaplica o bloqueio fora do foco quando uma flag muda.
    private let onBlockingSettingsChanged: () -> Void
    /// O escopo do seletor do foco mudou — o timer refiltra a lista.
    private let onFocusScopeChanged: () -> Void

    init(
        settings: SettingsRepository,
        loginItem: LoginItemManaging,
        authorizer: ProtectedActionAuthorizer,
        manageTasks: ManageTasksUseCase,
        onBlockingSettingsChanged: @escaping () -> Void,
        onFocusScopeChanged: @escaping () -> Void = {}
    ) {
        self.settings = settings
        self.loginItem = loginItem
        self.authorizer = authorizer
        self.manageTasks = manageTasks
        self.onBlockingSettingsChanged = onBlockingSettingsChanged
        self.onFocusScopeChanged = onFocusScopeChanged
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
        focusTaskScope = config.focusTaskScope
        launchAtLogin = loginItem.isEnabled
    }

    // MARK: - Tarefas no foco (RF-09.15)

    /// A aba Pomodoro está na tela; fora dela o relay não manda reler.
    private(set) var isPresented = false

    func didAppear() {
        isPresented = true
        reloadFocusScope()
    }

    func didDisappear() {
        isPresented = false
    }

    /// Relê escopo e tags: renomear/apagar tag na janela Tarefas mexe no escopo gravado, e tags
    /// novas precisam aparecer na lista de caixas.
    func reloadFocusScope() {
        focusTaskScope = settings.loadConfiguration().focusTaskScope
        knownTags = (try? manageTasks.allTags()) ?? []
    }

    // Regras de edição do escopo moram em `TaskScope` (Domain) — a aba Kanban usa as mesmas.
    var focusScopeIsByTag: Bool { focusTaskScope.isByTag }
    var selectableFocusTags: [String] { focusTaskScope.selectableTags(knownTags: knownTags) }
    func isFocusTagSelected(_ tag: String) -> Bool { focusTaskScope.contains(tag) }

    func setFocusScopeByTag(_ byTag: Bool) {
        guard let scope = focusTaskScope.switchingByTag(byTag) else { return }
        applyFocusScope(scope)
    }

    func setFocusTag(_ tag: String, selected: Bool) {
        applyFocusScope(focusTaskScope.settingTag(tag, selected: selected))
    }

    /// Único lugar que grava `focusTaskScope`: `save()` não o toca (ver lá).
    private func applyFocusScope(_ scope: TaskScope) {
        focusTaskScope = scope
        var config = settings.loadConfiguration()
        config.focusTaskScope = scope
        settings.save(config)
        onFocusScopeChanged()
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

    /// Persiste os campos que esta VM edita, **por cima da configuração gravada** — não monta uma
    /// `PomodoroConfiguration` do zero. `focusTaskScope` também é reescrito pelo
    /// `ManageTasksUseCase` (renomear/apagar tag) enquanto esta VM pode estar fora da tela com a
    /// cópia velha; gravá-la aqui a partir da memória desfaria aquela mudança no próximo toggle.
    func save() {
        var config = settings.loadConfiguration()
        config.focusDuration = focusMinutes * 60
        config.shortBreakDuration = shortBreakMinutes * 60
        config.longBreakDuration = longBreakMinutes * 60
        config.cyclesBeforeLongBreak = cyclesBeforeLongBreak
        config.autoAdvancePhases = autoAdvancePhases
        config.forceTerminateApps = forceTerminateApps
        // Vazio vira nil: o blocker interpreta nil como "página padrão".
        let redirect = blockedRedirectURL.trimmingCharacters(in: .whitespacesAndNewlines)
        config.blockedRedirectURL = redirect.isEmpty ? nil : redirect
        config.syncReminderCompletion = syncReminderCompletion
        config.allowMultipleTasksInFocus = allowMultipleTasksInFocus
        config.blockAppsWhileRunning = blockAppsWhileRunning
        config.blockSitesWhileRunning = blockSitesWhileRunning
        settings.save(config)
    }
}
