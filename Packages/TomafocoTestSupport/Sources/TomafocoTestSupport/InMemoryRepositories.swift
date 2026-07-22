import Foundation
import TomafocoDomain

/// Repositório de sessão em memória (failsafe testável sem tocar disco).
public final class InMemorySessionRepository: SessionRepository {
    public var active: PomodoroSession?
    public private(set) var history: [SessionRecord] = []
    public var saveActiveError: Error?

    public init(active: PomodoroSession? = nil) { self.active = active }

    public func saveActive(_ session: PomodoroSession) throws {
        if let saveActiveError { throw saveActiveError }
        active = session
    }
    public func loadActive() throws -> PomodoroSession? { active }
    public func clearActive() throws { active = nil }
    public func appendToHistory(_ record: SessionRecord) throws { history.append(record) }
}

/// Repositório de configurações/listas em memória.
public final class InMemorySettingsRepository: SettingsRepository {
    public var configuration: PomodoroConfiguration
    public var blockList: BlockList

    public init(
        configuration: PomodoroConfiguration = .init(),
        blockList: BlockList = .init()
    ) {
        self.configuration = configuration
        self.blockList = blockList
    }

    public func loadConfiguration() -> PomodoroConfiguration { configuration }
    public func save(_ configuration: PomodoroConfiguration) { self.configuration = configuration }
    public func loadBlockList() -> BlockList { blockList }
    public func save(_ blockList: BlockList) { self.blockList = blockList }
}
