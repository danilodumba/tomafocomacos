import Foundation

/// Persistência da sessão ativa (failsafe) e do histórico (RF-02.5, RF-07, UC-04).
public protocol SessionRepository: AnyObject {
    func saveActive(_ session: PomodoroSession) throws
    func loadActive() throws -> PomodoroSession?
    func clearActive() throws
    func appendToHistory(_ record: SessionRecord) throws
}

/// Persistência de configuração e listas de bloqueio (RF-05).
public protocol SettingsRepository: AnyObject {
    func loadConfiguration() -> PomodoroConfiguration
    func save(_ configuration: PomodoroConfiguration)
    func loadBlockList() -> BlockList
    func save(_ blockList: BlockList)
}

/// Envio de notificações locais ao usuário (RF-08).
public protocol UserNotifying: AnyObject {
    func notify(_ event: NotificationEvent)
}
