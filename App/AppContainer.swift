import Foundation
import SwiftUI
import TomafocoDomain
import TomafocoApplication
import TomafocoInfrastructure

/// Composition Root: ÚNICO lugar onde as implementações concretas são instanciadas e injetadas.
/// Trocar um adapter (ex.: AppleScript → XPC helper na v2) muda apenas este arquivo (OCP/DIP).
@MainActor
final class AppContainer: ObservableObject {

    /// Página local exibida no lugar do site bloqueado. Fica nos Resources do app.
    private static var blockPageURL: String {
        Bundle.main.url(forResource: "blocked", withExtension: "html")?.absoluteString
            ?? "about:blank"
    }

    let coordinator: SessionCoordinator
    let recover: RecoverFromCrashUseCase
    let manageBlockList: ManageBlockListUseCase

    let timerViewModel: TimerViewModel
    let settingsViewModel: SettingsViewModel
    let blockListViewModel: BlockListViewModel

    private let notificationAdapter: UNNotificationAdapter?

    private init(
        coordinator: SessionCoordinator,
        recover: RecoverFromCrashUseCase,
        manageBlockList: ManageBlockListUseCase,
        settings: SettingsRepository,
        appPicker: ApplicationPicking,
        notificationAdapter: UNNotificationAdapter?
    ) {
        self.coordinator = coordinator
        self.recover = recover
        self.manageBlockList = manageBlockList
        self.notificationAdapter = notificationAdapter
        self.timerViewModel = TimerViewModel(coordinator: coordinator, settings: settings)
        self.settingsViewModel = SettingsViewModel(settings: settings)
        self.blockListViewModel = BlockListViewModel(useCase: manageBlockList, appPicker: appPicker)
    }

    /// Monta o grafo real de dependências do macOS.
    static func live() -> AppContainer {
        // Som + Dock pulando no fim de cada etapa, por cima da notificação do sistema (RF-08.1).
        // O decorador garante o aviso mesmo se o usuário tiver negado notificações.
        let notificationAdapter = UNNotificationAdapter()
        let notifier = PhaseAlertNotifier(
            wrapping: notificationAdapter,
            sound: SystemSoundPlayer(),
            attention: DockAttentionRequester()
        )

        // Bloqueio de sites por automação do navegador (ADR-8). Substituiu o /etc/hosts:
        // sem root, sem senha e imune a DNS de VPN / DNS-over-HTTPS. Ver `AppleScriptBrowserBlocker`.
        let websiteBlocker = AppleScriptBrowserBlocker(
            blockPageURL: Self.blockPageURL,
            scriptRunner: NSAppleScriptRunner(),
            runningApps: WorkspaceRunningApplications()
        )
        let appBlocker = WorkspaceAppBlocker(notifier: notifier)
        let clock = DispatchSessionClock()
        let sessions = FileSessionSnapshotStore()
        let settings = UserDefaultsSettingsStore()

        let coordinator = SessionCoordinator(
            clock: clock, appBlocker: appBlocker, websiteBlocker: websiteBlocker,
            sessions: sessions, settings: settings, notifier: notifier
        )
        let recover = RecoverFromCrashUseCase(
            sessions: sessions, websiteBlocker: websiteBlocker,
            appBlocker: appBlocker, clock: clock
        )
        let manageBlockList = ManageBlockListUseCase(settings: settings)
        let appPicker = NSOpenPanelApplicationPicker()

        notificationAdapter.requestAuthorization()

        return AppContainer(
            coordinator: coordinator, recover: recover, manageBlockList: manageBlockList,
            settings: settings, appPicker: appPicker, notificationAdapter: notificationAdapter
        )
    }

    /// Executado na abertura da janela: resolve sessões órfãs (UC-04).
    func recoverFromCrashIfNeeded() async {
        let result = await recover.execute()
        timerViewModel.handleRecovery(result, recover: recover)
    }
}
