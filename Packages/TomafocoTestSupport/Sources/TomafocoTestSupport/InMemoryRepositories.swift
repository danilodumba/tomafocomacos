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
    public func loadHistory() throws -> [SessionRecord] { history }
}

/// Repositório de tarefas em memória (RF-09).
public final class InMemoryTaskRepository: TaskRepository {
    public var tasks: [FocusTask]
    public var loadError: Error?
    public var saveError: Error?

    public init(tasks: [FocusTask] = []) { self.tasks = tasks }

    public func loadTasks() throws -> [FocusTask] {
        if let loadError { throw loadError }
        return tasks
    }

    public func saveTasks(_ tasks: [FocusTask]) throws {
        if let saveError { throw saveError }
        self.tasks = tasks
    }
}

/// Importador de lembretes controlável pelos testes.
public final class StubTaskImporter: TaskImporting {
    public var accessGranted = true
    public var reminders: [ImportedReminder] = []
    public var lists: [ReminderList] = []
    public var fetchError: Error?
    public var listsError: Error?
    /// Último filtro pedido em `fetchIncompleteReminders` — os testes verificam o repasse.
    public private(set) var lastRequestedListIDs: Set<String>?
    public private(set) var fetchCallCount = 0
    /// Registro das gravações de conclusão pedidas via `setReminderCompleted` (os testes conferem).
    public private(set) var completionWriteBacks: [(reminderID: String, completed: Bool)] = []
    public var setCompletedResult = true

    public init() {}

    public func requestAccess() async -> Bool { accessGranted }

    public func fetchReminderLists() async throws -> [ReminderList] {
        if let listsError { throw listsError }
        return lists
    }

    public func fetchIncompleteReminders(fromLists lists: Set<String>?) async throws -> [ImportedReminder] {
        fetchCallCount += 1
        lastRequestedListIDs = lists
        if let fetchError { throw fetchError }
        return reminders
    }

    public func setReminderCompleted(reminderID: String, completed: Bool) async -> Bool {
        completionWriteBacks.append((reminderID, completed))
        return setCompletedResult
    }
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
