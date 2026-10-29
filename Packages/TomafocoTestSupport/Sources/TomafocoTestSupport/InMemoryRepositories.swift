import Foundation
import TomafocoDomain

/// Repositório de sessão em memória (failsafe testável sem tocar disco).
@MainActor
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
@MainActor
public final class InMemoryTaskRepository: TaskRepository {
    public var tasks: [FocusTask]
    public var loadError: Error?
    public var saveError: Error?
    /// Gravações feitas — os testes conferem que operações compostas gravam uma vez só.
    public private(set) var saveCallCount = 0

    public init(tasks: [FocusTask] = []) { self.tasks = tasks }

    public func loadTasks() throws -> [FocusTask] {
        if let loadError { throw loadError }
        return tasks
    }

    public func saveTasks(_ tasks: [FocusTask]) throws {
        if let saveError { throw saveError }
        saveCallCount += 1
        self.tasks = tasks
    }

    public func task(id: UUID) throws -> FocusTask? {
        if let loadError { throw loadError }
        return tasks.first { $0.id == id }
    }

    /// Conta como uma gravação, igual ao `saveTasks` — os testes de "grava uma vez só" valem
    /// para os dois caminhos.
    public func upsert(_ changed: [FocusTask]) throws {
        if let saveError { throw saveError }
        saveCallCount += 1
        for task in changed {
            if let idx = tasks.firstIndex(where: { $0.id == task.id }) {
                tasks[idx] = task
            } else {
                tasks.append(task)
            }
        }
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

/// Quadro Kanban em memória (FEAT-005). `nil` = nunca salvo.
@MainActor
public final class InMemoryKanbanBoardRepository: KanbanBoardRepository {
    public var board: KanbanBoard?
    public var saveError: Error?
    public private(set) var saveCount = 0

    public init(board: KanbanBoard? = nil) { self.board = board }

    public func loadBoard() throws -> KanbanBoard? { board }

    public func saveBoard(_ board: KanbanBoard) throws {
        if let saveError { throw saveError }
        saveCount += 1
        self.board = board
    }
}

/// Projetos em memória (FEAT-006).
@MainActor
public final class InMemoryProjectRepository: ProjectRepository {
    public var projects: [Project]
    public var saveError: Error?

    public init(projects: [Project] = []) { self.projects = projects }

    public func loadProjects() throws -> [Project] { projects }

    public func project(id: UUID) throws -> Project? { projects.first { $0.id == id } }

    public func upsert(_ project: Project) throws {
        if let saveError { throw saveError }
        if let idx = projects.firstIndex(where: { $0.id == project.id }) {
            projects[idx] = project
        } else {
            projects.append(project)
        }
    }

    public func delete(id: UUID) throws {
        if let saveError { throw saveError }
        projects.removeAll { $0.id == id }
    }
}

/// Transação em memória (FEAT-006): fotografa os repositórios antes do bloco e os restaura se
/// ele lançar — testa o rollback de verdade.
@MainActor
public final class InMemoryUnitOfWork: UnitOfWork {
    private let tasks: InMemoryTaskRepository?
    private let projects: InMemoryProjectRepository?
    public private(set) var performCount = 0

    public init(tasks: InMemoryTaskRepository? = nil, projects: InMemoryProjectRepository? = nil) {
        self.tasks = tasks
        self.projects = projects
    }

    public func perform<T>(_ work: () throws -> T) throws -> T {
        performCount += 1
        let taskSnapshot = tasks?.tasks
        let projectSnapshot = projects?.projects
        do {
            return try work()
        } catch {
            if let taskSnapshot { tasks?.tasks = taskSnapshot }
            if let projectSnapshot { projects?.projects = projectSnapshot }
            throw error
        }
    }
}
