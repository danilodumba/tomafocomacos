import Foundation

/// Configuração do ciclo Pomodoro. Sem números mágicos espalhados: durações vêm daqui (RF-01.2).
public struct PomodoroConfiguration: Equatable, Codable, Sendable {
    public var focusDuration: TimeInterval
    public var shortBreakDuration: TimeInterval
    public var longBreakDuration: TimeInterval
    public var cyclesBeforeLongBreak: Int
    /// Avança sozinho para a próxima etapa — foco → intervalo E intervalo → foco.
    /// Desligado, cada etapa termina avisando e espera confirmação do usuário.
    public var autoAdvancePhases: Bool
    public var forceTerminateApps: Bool
    /// Site para onde a aba bloqueada é redirecionada. `nil`/vazio → página de bloqueio padrão
    /// (`blocked.html`). A normalização (adicionar esquema) fica na Infra, onde é aplicada.
    public var blockedRedirectURL: String?
    /// Espelha a conclusão/reabertura de tarefas importadas de volta no app Lembretes (RF-09.3).
    public var syncReminderCompletion: Bool
    /// Permite selecionar mais de uma tarefa para uma mesma sessão de foco (RF-09.4).
    /// Desligado, o seletor volta a ser de tarefa única (comportamento padrão).
    public var allowMultipleTasksInFocus: Bool
    /// Mantém o bloqueio de apps ligado enquanto o Tomafoco estiver aberto, não só no foco (FEAT-002).
    public var blockAppsWhileRunning: Bool
    /// Mantém o bloqueio de sites ligado enquanto o Tomafoco estiver aberto, não só no foco (FEAT-002).
    public var blockSitesWhileRunning: Bool

    /// A chave persistida continua sendo `autoStartNextFocus`: renomear quebraria a
    /// decodificação das configurações já salvas, e o store cai silenciosamente no padrão
    /// quando a decodificação falha — o usuário perderia durações e ajustes sem aviso.
    private enum CodingKeys: String, CodingKey {
        case focusDuration, shortBreakDuration, longBreakDuration, cyclesBeforeLongBreak
        case autoAdvancePhases = "autoStartNextFocus"
        case forceTerminateApps, blockedRedirectURL, syncReminderCompletion
        case allowMultipleTasksInFocus
        case blockAppsWhileRunning, blockSitesWhileRunning
    }

    public init(
        focusDuration: TimeInterval = 25 * 60,
        shortBreakDuration: TimeInterval = 5 * 60,
        longBreakDuration: TimeInterval = 15 * 60,
        cyclesBeforeLongBreak: Int = 4,
        autoAdvancePhases: Bool = false,
        forceTerminateApps: Bool = false,
        blockedRedirectURL: String? = nil,
        syncReminderCompletion: Bool = true,
        allowMultipleTasksInFocus: Bool = false,
        blockAppsWhileRunning: Bool = false,
        blockSitesWhileRunning: Bool = false
    ) {
        self.focusDuration = focusDuration
        self.shortBreakDuration = shortBreakDuration
        self.longBreakDuration = longBreakDuration
        self.cyclesBeforeLongBreak = cyclesBeforeLongBreak
        self.autoAdvancePhases = autoAdvancePhases
        self.forceTerminateApps = forceTerminateApps
        self.blockedRedirectURL = blockedRedirectURL
        self.syncReminderCompletion = syncReminderCompletion
        self.allowMultipleTasksInFocus = allowMultipleTasksInFocus
        self.blockAppsWhileRunning = blockAppsWhileRunning
        self.blockSitesWhileRunning = blockSitesWhileRunning
    }

    // Decode tolerante a chaves ausentes: `syncReminderCompletion` (e qualquer campo futuro)
    // gravado antes de existir cai no padrão em vez de derrubar TODA a config para o padrão
    // (o store reseta tudo se a decodificação lançar). `encode` continua sintetizado.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = PomodoroConfiguration()
        focusDuration = try c.decodeIfPresent(TimeInterval.self, forKey: .focusDuration) ?? d.focusDuration
        shortBreakDuration = try c.decodeIfPresent(TimeInterval.self, forKey: .shortBreakDuration) ?? d.shortBreakDuration
        longBreakDuration = try c.decodeIfPresent(TimeInterval.self, forKey: .longBreakDuration) ?? d.longBreakDuration
        cyclesBeforeLongBreak = try c.decodeIfPresent(Int.self, forKey: .cyclesBeforeLongBreak) ?? d.cyclesBeforeLongBreak
        autoAdvancePhases = try c.decodeIfPresent(Bool.self, forKey: .autoAdvancePhases) ?? d.autoAdvancePhases
        forceTerminateApps = try c.decodeIfPresent(Bool.self, forKey: .forceTerminateApps) ?? d.forceTerminateApps
        blockedRedirectURL = try c.decodeIfPresent(String.self, forKey: .blockedRedirectURL)
        syncReminderCompletion = try c.decodeIfPresent(Bool.self, forKey: .syncReminderCompletion) ?? d.syncReminderCompletion
        allowMultipleTasksInFocus = try c.decodeIfPresent(Bool.self, forKey: .allowMultipleTasksInFocus) ?? d.allowMultipleTasksInFocus
        blockAppsWhileRunning = try c.decodeIfPresent(Bool.self, forKey: .blockAppsWhileRunning) ?? d.blockAppsWhileRunning
        blockSitesWhileRunning = try c.decodeIfPresent(Bool.self, forKey: .blockSitesWhileRunning) ?? d.blockSitesWhileRunning
    }

    /// Duração de uma dada fase segundo esta configuração.
    public func duration(for phase: SessionPhase) -> TimeInterval {
        switch phase {
        case .idle: return 0
        case .focus: return focusDuration
        case .shortBreak: return shortBreakDuration
        case .longBreak: return longBreakDuration
        }
    }
}
