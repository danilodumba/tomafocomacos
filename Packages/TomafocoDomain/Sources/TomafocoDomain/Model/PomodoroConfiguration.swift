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
    public var hardcore: HardcoreOptions

    /// A chave persistida continua sendo `autoStartNextFocus`: renomear quebraria a
    /// decodificação das configurações já salvas, e o store cai silenciosamente no padrão
    /// quando a decodificação falha — o usuário perderia durações e ajustes sem aviso.
    private enum CodingKeys: String, CodingKey {
        case focusDuration, shortBreakDuration, longBreakDuration, cyclesBeforeLongBreak
        case autoAdvancePhases = "autoStartNextFocus"
        case forceTerminateApps, hardcore
    }

    public init(
        focusDuration: TimeInterval = 25 * 60,
        shortBreakDuration: TimeInterval = 5 * 60,
        longBreakDuration: TimeInterval = 15 * 60,
        cyclesBeforeLongBreak: Int = 4,
        autoAdvancePhases: Bool = false,
        forceTerminateApps: Bool = false,
        hardcore: HardcoreOptions = .init()
    ) {
        self.focusDuration = focusDuration
        self.shortBreakDuration = shortBreakDuration
        self.longBreakDuration = longBreakDuration
        self.cyclesBeforeLongBreak = cyclesBeforeLongBreak
        self.autoAdvancePhases = autoAdvancePhases
        self.forceTerminateApps = forceTerminateApps
        self.hardcore = hardcore
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

/// Opções do modo hardcore (RF-06).
public struct HardcoreOptions: Equatable, Codable, Sendable {
    public var isEnabled: Bool
    public var minimumMinutesBeforeCancel: Int
    public var requireReason: Bool

    public init(isEnabled: Bool = false, minimumMinutesBeforeCancel: Int = 5, requireReason: Bool = true) {
        self.isEnabled = isEnabled
        self.minimumMinutesBeforeCancel = minimumMinutesBeforeCancel
        self.requireReason = requireReason
    }
}
