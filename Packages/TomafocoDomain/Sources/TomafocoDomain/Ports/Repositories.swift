import Foundation

// Ports de persistência são `@MainActor` (FEAT-006, ADR-11): o adapter SwiftData usa o
// `mainContext`, que não é `Sendable`. Isolar o port inteiro faz o compilador barrar qualquer
// acesso fora da main — inclusive depois de um `await` dentro de um use case.

/// Persistência da sessão ativa (failsafe) e do histórico (RF-02.5, RF-07, UC-04).
@MainActor
public protocol SessionRepository: AnyObject {
    func saveActive(_ session: PomodoroSession) throws
    func loadActive() throws -> PomodoroSession?
    func clearActive() throws
    func appendToHistory(_ record: SessionRecord) throws
    func loadHistory() throws -> [SessionRecord]
}

/// Persistência das tarefas de foco (RF-09).
@MainActor
public protocol TaskRepository: AnyObject {
    func loadTasks() throws -> [FocusTask]
    /// Grava o **estado completo** desejado (operações que mexem em várias tarefas: cascata,
    /// apagar raia, importação). O adapter de banco grava só o que mudou — diff por `id`:
    /// atualiza as alteradas, insere as novas e apaga as que sumiram.
    func saveTasks(_ tasks: [FocusTask]) throws
    func task(id: UUID) throws -> FocusTask?
    /// Insere ou atualiza só estas tarefas — o caminho de uma edição pontual.
    func upsert(_ tasks: [FocusTask]) throws
}

/// Persistência do quadro Kanban (FEAT-005): raias + configuração do quadro.
/// `nil` = nunca salvo (o use case cria o quadro padrão).
@MainActor
public protocol KanbanBoardRepository: AnyObject {
    func loadBoard() throws -> KanbanBoard?
    func saveBoard(_ board: KanbanBoard) throws
}

/// Projetos (FEAT-006). Volume pequeno: leitura sempre da lista inteira.
@MainActor
public protocol ProjectRepository: AnyObject {
    func loadProjects() throws -> [Project]
    /// Existência/leitura de um só — o caminho quente (`requireProject` a cada criação/edição
    /// de tarefa) não precisa decodificar a tabela inteira.
    func project(id: UUID) throws -> Project?
    func upsert(_ project: Project) throws
    func delete(id: UUID) throws
}

/// Transação que abrange vários repositórios (FEAT-006): o que é gravado dentro de `perform`
/// só vai para o disco no fim, e um erro desfaz tudo. Ex.: apagar projeto + tirar o projeto das
/// tarefas — metade feita deixaria tarefas apontando para projeto inexistente.
@MainActor
public protocol UnitOfWork: AnyObject {
    func perform<T>(_ work: () throws -> T) throws -> T
}

/// Catálogo de tags "cadastradas" (RF-09.5) — inclusive tags criadas na tela de gestão que
/// ainda não estão em nenhuma tarefa. Best-effort (UserDefaults): não lança. As tags em uso pelas
/// tarefas continuam sendo a fonte primária; o catálogo só guarda as órfãs e as renomeações.
@MainActor
public protocol TagCatalog: AnyObject {
    func loadTags() -> [String]
    func saveTags(_ tags: [String])
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
