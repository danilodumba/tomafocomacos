import Foundation

/// Propaga "as tarefas mudaram" entre as telas que mostram tarefas (FEAT-005): lista, janelas
/// Kanban (uma por quadro — FEAT-008 —, podem estar abertas lado a lado), abas Kanban e Pomodoro
/// das Configurações (tags renomeadas na lista mudam os escopos por tag), os menus de quadros e
/// o seletor do timer. Quem originou a mudança já se releu;
/// os demais recebem `refresh()`, que não avisa de volta. Tela que não está visível não relê
/// (seria leitura de disco à toa) — ela relê sozinha ao aparecer.
@MainActor
final class TaskChangeRelay {
    enum Source {
        case list
        /// Uma janela Kanban — só ela é poupada; as janelas dos outros quadros relêem.
        case board(KanbanViewModel)
        case settings
    }

    private let timer: TimerViewModel
    private weak var list: TasksViewModel?
    /// Janelas Kanban abertas (FEAT-008) — uma por quadro, registradas ao nascer.
    private let boards = NSHashTable<KanbanViewModel>.weakObjects()
    private weak var boardList: KanbanBoardList?
    private weak var boardSettings: KanbanSettingsViewModel?
    private weak var focusSettings: SettingsViewModel?
    /// Selo "tem documento" (FEAT-007): apagar tarefa e clonar diária mexem nos documentos.
    private let documentIndex: TaskDocumentIndex
    /// Janelas de documento abertas — relêem título/existência da tarefa (só a tarefa delas).
    private let documentWindows = NSHashTable<DocumentViewModel>.weakObjects()

    init(timer: TimerViewModel, documentIndex: TaskDocumentIndex) {
        self.timer = timer
        self.documentIndex = documentIndex
    }

    func register(documentWindow: DocumentViewModel) {
        documentWindows.add(documentWindow)
    }

    func register(board: KanbanViewModel) {
        boards.add(board)
    }

    func connect(list: TasksViewModel, boardList: KanbanBoardList,
                 boardSettings: KanbanSettingsViewModel, focusSettings: SettingsViewModel) {
        self.list = list
        self.boardList = boardList
        self.boardSettings = boardSettings
        self.focusSettings = focusSettings
    }

    func tasksChanged(from source: Source) {
        if case .list = source {} else { list?.refresh() }
        for board in boards.allObjects where board.isPresented {
            if case .board(let origin) = source, origin === board { continue }
            board.refresh()
        }
        if let boardSettings, boardSettings.isPresented {
            if case .settings = source {} else { boardSettings.reload() }
        }
        boardList?.reload()
        if let focusSettings, focusSettings.isPresented { focusSettings.reloadFocusScope() }
        timer.reloadAvailableTasks()
        documentIndex.reload()
        documentWindows.allObjects.forEach { $0.refresh() }
    }
}
