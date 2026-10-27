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

    init(timer: TimerViewModel) {
        self.timer = timer
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
    }
}
