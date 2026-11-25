import Foundation

/// Propaga "as tarefas mudaram" entre as telas que mostram tarefas (FEAT-005): lista, Kanban
/// (podem estar abertas lado a lado), abas Kanban e Pomodoro das Configurações (tags renomeadas
/// na lista mudam os escopos por tag) e o seletor do timer. Quem originou a mudança já se releu;
/// os demais recebem `refresh()`, que não avisa de volta. Tela que não está visível não relê
/// (seria leitura de disco à toa) — ela relê sozinha ao aparecer.
@MainActor
final class TaskChangeRelay {
    enum Source { case list, board, settings }

    private let timer: TimerViewModel
    private weak var list: TasksViewModel?
    private weak var board: KanbanViewModel?
    private weak var boardSettings: KanbanSettingsViewModel?
    private weak var focusSettings: SettingsViewModel?
    /// Selo "tem documento" (FEAT-007): apagar tarefa e clonar diária mexem nos documentos.
    private let documentIndex: TaskDocumentIndex
    /// Janelas de documento abertas — relêem título/existência da tarefa (só a tarefa delas).
    private let documentWindows = NSHashTable<TaskDocumentViewModel>.weakObjects()

    init(timer: TimerViewModel, documentIndex: TaskDocumentIndex) {
        self.timer = timer
        self.documentIndex = documentIndex
    }

    func register(documentWindow: TaskDocumentViewModel) {
        documentWindows.add(documentWindow)
    }

    func connect(list: TasksViewModel, board: KanbanViewModel,
                 boardSettings: KanbanSettingsViewModel, focusSettings: SettingsViewModel) {
        self.list = list
        self.board = board
        self.boardSettings = boardSettings
        self.focusSettings = focusSettings
    }

    func tasksChanged(from source: Source) {
        if source != .list { list?.refresh() }
        if source != .board, let board, board.isPresented { board.refresh() }
        if source != .settings, let boardSettings, boardSettings.isPresented { boardSettings.reload() }
        if let focusSettings, focusSettings.isPresented { focusSettings.reloadFocusScope() }
        timer.reloadAvailableTasks()
        documentIndex.reload()
        documentWindows.allObjects.forEach { $0.refresh() }
    }
}
