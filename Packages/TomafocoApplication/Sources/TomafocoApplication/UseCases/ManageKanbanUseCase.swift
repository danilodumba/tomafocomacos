import Foundation
import TomafocoDomain

/// Quadro Kanban (FEAT-005): raias, configuração do quadro e movimentação de tarefas.
///
/// Conclusão/reabertura passam pelo `ManageTasksUseCase` — inclusive o espelhamento no
/// Lembretes e a regra da tarefa diária —, então mover para a raia Done é exatamente o mesmo
/// que concluir pela lista. Cada movimentação vira uma entrada no histórico da tarefa.
public final class ManageKanbanUseCase {
    private let boards: KanbanBoardRepository
    private let tasks: ManageTasksUseCase
    private let now: () -> Date
    private let makeID: () -> UUID

    // `now` sem default de propósito: `Date()` é proibido na Application.
    public init(
        boards: KanbanBoardRepository,
        tasks: ManageTasksUseCase,
        now: @escaping () -> Date,
        makeID: @escaping () -> UUID = { UUID() }
    ) {
        self.boards = boards
        self.tasks = tasks
        self.now = now
        self.makeID = makeID
    }

    /// Quadro salvo ou, na primeira vez, o padrão (já gravado).
    public func board() throws -> KanbanBoard {
        if let saved = try boards.loadBoard() { return saved }
        let board = KanbanBoard.makeDefault(makeID: makeID)
        try boards.saveBoard(board)
        return board
    }

    // MARK: - Configuração do quadro

    /// Dias que a concluída fica na raia Done — limitado a `KanbanBoard.doneRetentionRange`.
    @discardableResult
    public func setDoneRetentionDays(_ days: Int) throws -> KanbanBoard {
        try mutateBoard { $0.doneRetentionDays = days }
    }

    /// Quais tarefas entram no quadro. Tags normalizadas (sem vazias/duplicatas por caixa).
    @discardableResult
    public func setTaskScope(_ scope: TaskScope) throws -> KanbanBoard {
        let normalized: TaskScope
        switch scope {
        case .all: normalized = .all
        case .tags(let selected): normalized = .tags(FocusTask.normalizeTags(selected))
        }
        return try mutateBoard { $0.taskScope = normalized }
    }

    // MARK: - Raias

    @discardableResult
    public func addLane(title: String) throws -> KanbanBoard {
        let id = makeID()
        return try mutateBoard { try $0.addLane(id: id, title: title) }
    }

    @discardableResult
    public func renameLane(id: UUID, title: String) throws -> KanbanBoard {
        try mutateBoard { try $0.renameLane(id: id, title: title) }
    }

    /// Reposiciona uma raia aberta (índice entre as abertas). A Done fica fixa no fim.
    @discardableResult
    public func moveLane(id: UUID, to index: Int) throws -> KanbanBoard {
        try mutateBoard { $0.moveOpenLane(id: id, to: index) }
    }

    /// Tarefas abertas que estão nesta raia — a UI pede confirmação antes de apagar.
    public func openTaskCount(inLane id: UUID) throws -> Int {
        let board = try board()
        return try tasks.allTasks().filter { !$0.isCompleted && board.lane(for: $0).id == id }.count
    }

    /// Apaga uma raia aberta. As tarefas abertas que ESTAVAM nela (pela mesma regra de
    /// `lane(for:)` que o quadro e a confirmação usam — inclui as sem `laneID` quando é a
    /// primeira raia) vão para a nova primeira raia com uma entrada de histórico; as concluídas
    /// só perdem a referência (estão na Done).
    ///
    /// Tarefas numa gravação só e ANTES do quadro: se a gravação das tarefas falhar, nada
    /// mudou; se a do quadro falhar depois, as tarefas já apontam para a raia destino (válida
    /// nos dois quadros) e a raia some na próxima tentativa.
    @discardableResult
    public func deleteLane(id: UUID) throws -> KanbanBoard {
        let before = try board()
        var after = before
        guard let removed = try after.removeLane(id: id) else { return before }

        let destination = after.firstOpenLane
        let text = "Movida: \(removed.title) → \(destination.title) (raia removida)"
        let updated = try tasks.allTasks().map { task -> FocusTask in
            var task = task
            if task.isCompleted {
                if task.laneID == id { task.laneID = nil }
            } else if before.lane(for: task).id == id {
                task.laneID = destination.id
                task.history.append(TaskHistoryEntry(id: makeID(), createdAt: now(), text: text))
            }
            return task
        }
        try tasks.replaceAll(updated)
        try boards.saveBoard(after)
        return after
    }

    // MARK: - Movimentação

    /// Move a tarefa para outra raia — único ponto de movimentação do quadro.
    ///
    /// - Para a Done: conclui (com espelhamento no Lembretes). Diária registra a conclusão do dia
    ///   e volta para a primeira raia, já que nunca fica concluída (FEAT-004).
    /// - Saindo da Done: reabre e entra na raia destino.
    /// - Entre raias abertas: só grava a raia.
    ///
    /// Grava `"Movida: <origem> → <destino>"` no histórico. Mesma raia, tarefa ou raia
    /// inexistente: no-op. Devolve o resultado do espelhamento para a UI avisar falha.
    @discardableResult
    public func moveTask(id: UUID, toLane laneID: UUID) async throws -> ReminderSyncOutcome {
        let board = try board()
        var all = try tasks.allTasks()
        guard let idx = all.firstIndex(where: { $0.id == id }),
              let target = board.lane(id: laneID) else { return .notApplicable }
        let origin = board.lane(for: all[idx])
        guard origin.id != target.id else { return .notApplicable }

        // Conclusão/reabertura + raia + histórico numa gravação só; o espelhamento no Lembretes
        // vem depois, sobre o estado já gravado (best-effort, como na lista). Para a Done, a
        // conclusão é em cascata (FEAT-003): as subtarefas abertas fecham junto e, como a raia
        // é derivada da conclusão, os cartões delas vão para a Done também.
        let entry = TaskHistoryEntry(id: makeID(), createdAt: now(), text: "Movida: \(origin.title) → \(target.title)")
        // Saindo da Done, uma subtarefa reabre também o pai concluído (invariante "subtarefa
        // ativa ⇒ pai ativo") — o cartão do pai volta à raia que ele tinha.
        var reopenedParent: FocusTask?
        if target.isDone {
            tasks.applyCompletionCascade(id: id, in: &all)
        } else if origin.isDone {
            reopenedParent = tasks.applyReopenCascade(id: id, in: &all)?.reopenedParent
        }
        all[idx].history.append(entry)
        if !target.isDone {
            all[idx].laneID = target.id
        }
        // Concluída mantém o `laneID`: reabrir pela lista a devolve à raia de antes. Diária
        // (FEAT-004) idem — o clone para amanhã que a cascata acrescentou nasce sem raia (1ª).
        try tasks.replaceAll(all)
        guard target.isDone || origin.isDone else { return .notApplicable }
        let outcome = await tasks.syncCompletion(of: all[idx])
        guard let reopenedParent else { return outcome }
        let parentOutcome = await tasks.syncCompletion(of: reopenedParent)
        if outcome == .failed || parentOutcome == .failed { return .failed }
        return outcome == .notApplicable ? parentOutcome : outcome
    }

    // MARK: - Helpers

    private func mutateBoard(_ mutate: (inout KanbanBoard) throws -> Void) throws -> KanbanBoard {
        var board = try board()
        try mutate(&board)
        try boards.saveBoard(board)
        return board
    }
}
