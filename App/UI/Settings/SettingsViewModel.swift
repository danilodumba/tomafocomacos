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
    @Published var autoStartNextFocus: Bool { didSet { save() } }
    @Published var forceTerminateApps: Bool { didSet { save() } }
    @Published var hardcoreEnabled: Bool { didSet { save() } }
    @Published var hardcoreGraceMinutes: Int { didSet { save() } }
    @Published var hardcoreRequireReason: Bool { didSet { save() } }

    private let settings: SettingsRepository

    init(settings: SettingsRepository) {
        self.settings = settings
        // Observadores de propriedade não disparam durante a init — nenhum save espúrio aqui.
        let config = settings.loadConfiguration()
        focusMinutes = config.focusDuration / 60
        shortBreakMinutes = config.shortBreakDuration / 60
        longBreakMinutes = config.longBreakDuration / 60
        cyclesBeforeLongBreak = config.cyclesBeforeLongBreak
        autoStartNextFocus = config.autoStartNextFocus
        forceTerminateApps = config.forceTerminateApps
        hardcoreEnabled = config.hardcore.isEnabled
        hardcoreGraceMinutes = config.hardcore.minimumMinutesBeforeCancel
        hardcoreRequireReason = config.hardcore.requireReason
    }

    /// Persiste a configuração atual.
    func save() {
        let config = PomodoroConfiguration(
            focusDuration: focusMinutes * 60,
            shortBreakDuration: shortBreakMinutes * 60,
            longBreakDuration: longBreakMinutes * 60,
            cyclesBeforeLongBreak: cyclesBeforeLongBreak,
            autoStartNextFocus: autoStartNextFocus,
            forceTerminateApps: forceTerminateApps,
            hardcore: HardcoreOptions(
                isEnabled: hardcoreEnabled,
                minimumMinutesBeforeCancel: hardcoreGraceMinutes,
                requireReason: hardcoreRequireReason
            )
        )
        settings.save(config)
    }
}
