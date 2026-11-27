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

/// Quadros Kanban em memória (FEAT-005/FEAT-008). Vazio = nunca salvo.
@MainActor
public final class InMemoryKanbanBoardRepository: KanbanBoardRepository {
    public var boards: [KanbanBoard]
    public var saveError: Error?
    public private(set) var saveCount = 0

    public init(boards: [KanbanBoard] = []) { self.boards = boards }

    /// Atalho para os testes de um quadro só: o primeiro da lista.
    public var board: KanbanBoard? { boards.first }

    public func loadBoards() throws -> [KanbanBoard] { boards }

    public func saveBoards(_ boards: [KanbanBoard]) throws {
        if let saveError { throw saveError }
        saveCount += 1
        self.boards = boards
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

/// Documentos das tarefas em memória (FEAT-007).
@MainActor
public final class InMemoryTaskDocumentRepository: TaskDocumentRepository {
    public var documents: [UUID: TaskDocument]
    public var saveError: Error?

    public init(documents: [TaskDocument] = []) {
        self.documents = Dictionary(uniqueKeysWithValues: documents.map { ($0.taskID, $0) })
    }

    public func document(taskID: UUID) throws -> TaskDocument? { documents[taskID] }

    public func save(_ document: TaskDocument) throws {
        if let saveError { throw saveError }
        documents[document.taskID] = document
    }

    public func delete(taskIDs: Set<UUID>) throws {
        if let saveError { throw saveError }
        taskIDs.forEach { documents[$0] = nil }
    }

    public func taskIDsWithDocument() throws -> Set<UUID> { Set(documents.keys) }
}

/// Documentos dos projetos em memória (FEAT-009).
@MainActor
public final class InMemoryProjectDocumentRepository: ProjectDocumentRepository {
    public var documents: [UUID: ProjectDocument] = [:]
    public var saveError: Error?
    public var deleteError: Error?
    public private(set) var saveCount = 0

    public init() {}

    public func summaries(projectID: UUID) throws -> [ProjectDocumentSummary] {
        documents.values.filter { $0.projectID == projectID }.map(\.summary)
    }

    public func document(id: UUID) throws -> ProjectDocument? { documents[id] }

    public func save(_ document: ProjectDocument) throws {
        if let saveError { throw saveError }
        saveCount += 1
        documents[document.id] = document
    }

    public func delete(id: UUID) throws {
        if let deleteError { throw deleteError }
        documents[id] = nil
    }

    public func delete(projectID: UUID) throws {
        if let deleteError { throw deleteError }
        documents = documents.filter { $0.value.projectID != projectID }
    }
}

/// Transação em memória (FEAT-006): fotografa os repositórios antes do bloco e os restaura se
/// ele lançar — testa o rollback de verdade.
@MainActor
public final class InMemoryUnitOfWork: UnitOfWork {
    private let tasks: InMemoryTaskRepository?
    private let projects: InMemoryProjectRepository?
    private let documents: InMemoryTaskDocumentRepository?
    private let projectDocuments: InMemoryProjectDocumentRepository?
    public private(set) var performCount = 0

    public init(tasks: InMemoryTaskRepository? = nil, projects: InMemoryProjectRepository? = nil,
                documents: InMemoryTaskDocumentRepository? = nil,
                projectDocuments: InMemoryProjectDocumentRepository? = nil) {
        self.tasks = tasks
        self.projects = projects
        self.documents = documents
        self.projectDocuments = projectDocuments
    }

    public func perform<T>(_ work: () throws -> T) throws -> T {
        performCount += 1
        let taskSnapshot = tasks?.tasks
        let projectSnapshot = projects?.projects
        let documentSnapshot = documents?.documents
        let projectDocumentSnapshot = projectDocuments?.documents
        do {
            return try work()
        } catch {
            if let taskSnapshot { tasks?.tasks = taskSnapshot }
            if let projectSnapshot { projects?.projects = projectSnapshot }
            if let documentSnapshot { documents?.documents = documentSnapshot }
            if let projectDocumentSnapshot { projectDocuments?.documents = projectDocumentSnapshot }
            throw error
        }
    }
}
