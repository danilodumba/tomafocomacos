import Foundation

/// Configuração do ciclo Pomodoro. Sem números mágicos espalhados: durações vêm daqui (RF-01.2).
public struct PomodoroConfiguration: Equatable, Codable, Sendable {
    public var focusDuration: TimeInterval
    public var shortBreakDuration: TimeInterval
    public var longBreakDuration: TimeInterval
    public var cyclesBeforeLongBreak: Int
    public var autoStartNextFocus: Bool
    public var forceTerminateApps: Bool
    public var hardcore: HardcoreOptions

    public init(
        focusDuration: TimeInterval = 25 * 60,
        shortBreakDuration: TimeInterval = 5 * 60,
        longBreakDuration: TimeInterval = 15 * 60,
        cyclesBeforeLongBreak: Int = 4,
        autoStartNextFocus: Bool = false,
        forceTerminateApps: Bool = false,
        hardcore: HardcoreOptions = .init()
    ) {
        self.focusDuration = focusDuration
        self.shortBreakDuration = shortBreakDuration
        self.longBreakDuration = longBreakDuration
        self.cyclesBeforeLongBreak = cyclesBeforeLongBreak
        self.autoStartNextFocus = autoStartNextFocus
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
