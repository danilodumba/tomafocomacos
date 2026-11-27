import Foundation
import TomafocoDomain

/// Quadros Kanban (FEAT-005, vários desde a FEAT-008): quadros, raias, configuração de cada
/// quadro e movimentação de tarefas.
///
/// Conclusão/reabertura passam pelo `ManageTasksUseCase` — inclusive o espelhamento no
/// Lembretes e a regra da tarefa diária —, então mover para a raia Done é exatamente o mesmo
/// que concluir pela lista. A conclusão é **global**: concluída aparece na Done de todos os
/// quadros que a incluem. Cada movimentação vira uma entrada no histórico da tarefa.
///
/// Toda operação de quadro recebe o `boardID` explícito: a UI sempre sabe em que quadro está, e
/// um quadro apagado em outra janela vira `boardNotFound` em vez de agir no quadro errado.
@MainActor
public final class ManageKanbanUseCase {
    private let repository: KanbanBoardRepository
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
        self.repository = boards
        self.tasks = tasks
        self.now = now
        self.makeID = makeID
    }

    // MARK: - Quadros (FEAT-008)

    /// Quadros na ordem de criação. Na primeira vez (nenhum gravado), cria e grava o padrão —
    /// sempre existe pelo menos um.
    public func boards() throws -> [KanbanBoard] {
        let saved = try repository.loadBoards()
        if !saved.isEmpty { return saved }
        let board = KanbanBoard.makeDefault(makeID: makeID)
        try repository.saveBoards([board])
        return [board]
    }

    /// Quadro pelo id; inexistente → `boardNotFound`.
    public func board(id: UUID) throws -> KanbanBoard {
        guard let board = try boards().first(where: { $0.id == id }) else { throw DomainError.boardNotFound }
        return board
    }

    /// Quadro novo, no fim da lista, com as raias padrão. Nome com trim, obrigatório e único
    /// sem distinção de caixa (`emptyBoardName`/`duplicateBoardName`).
    @discardableResult
    public func createBoard(name: String) throws -> KanbanBoard {
        var all = try boards()
        let valid = try validName(name, excluding: nil, in: all)
        let board = KanbanBoard.makeDefault(name: valid, makeID: makeID)
        all.append(board)
        try repository.saveBoards(all)
        return board
    }

    /// Renomeia; a duplicata exclui o próprio quadro (salvar o mesmo nome não acusa).
    @discardableResult
    public func renameBoard(id: UUID, name: String) throws -> KanbanBoard {
        let all = try boards()
        let valid = try validName(name, excluding: id, in: all)
        return try mutateBoard(id) { try $0.rename(to: valid) }
    }

    /// Tarefas abertas que aparecem no quadro — a UI pede confirmação antes de apagar.
    public func openTaskCount(inBoard id: UUID) throws -> Int {
        let board = try board(id: id)
        let all = try tasks.allTasks()
        return all.filter { !$0.isCompleted && board.includes($0, in: all) }.count
    }

    /// Apaga o quadro. As tarefas **não** são apagadas: só perdem as raias deste quadro. O último
    /// quadro não sai (`cannotDeleteLastBoard`).
    ///
    /// Tarefas antes da lista de quadros, como no `deleteLane`: se a gravação das tarefas falhar,
    /// nada mudou; se a dos quadros falhar depois, as tarefas só perderam ids que voltariam a
    /// cair na 1ª raia do quadro que sobrou.
    public func deleteBoard(id: UUID) throws {
        var all = try boards()
        guard let idx = all.firstIndex(where: { $0.id == id }) else { throw DomainError.boardNotFound }
        guard all.count > 1 else { throw DomainError.cannotDeleteLastBoard }
        let removed = all.remove(at: idx)

        var list = try tasks.allTasks()
        var changed = false
        for taskIdx in list.indices where list[taskIdx].storedLaneID(in: removed) != nil {
            list[taskIdx].removeLanes(of: removed)
            changed = true
        }
        if changed { try tasks.replaceAll(list) }
        try repository.saveBoards(all)
    }

    // MARK: - Configuração do quadro

    /// Dias que a concluída fica na raia Done — limitado a `KanbanBoard.doneRetentionRange`.
    @discardableResult
    public func setDoneRetentionDays(_ days: Int, in boardID: UUID) throws -> KanbanBoard {
        try mutateBoard(boardID) { $0.doneRetentionDays = days }
    }

    /// Quais tarefas entram no quadro por tag. Tags normalizadas (sem vazias/duplicatas por caixa).
    @discardableResult
    public func setTaskScope(_ scope: TaskScope, in boardID: UUID) throws -> KanbanBoard {
        let normalized: TaskScope
        switch scope {
        case .all: normalized = .all
        case .tags(let selected): normalized = .tags(FocusTask.normalizeTags(selected))
        }
        return try mutateBoard(boardID) { $0.taskScope = normalized }
    }

    /// Quais tarefas entram no quadro por projeto (FEAT-008).
    @discardableResult
    public func setProjectScope(_ scope: ProjectFilter, in boardID: UUID) throws -> KanbanBoard {
        try mutateBoard(boardID) { $0.projectScope = scope }
    }

    // MARK: - Raias

    @discardableResult
    public func addLane(title: String, in boardID: UUID) throws -> KanbanBoard {
        let id = makeID()
        return try mutateBoard(boardID) { try $0.addLane(id: id, title: title) }
    }

    @discardableResult
    public func renameLane(id: UUID, title: String, in boardID: UUID) throws -> KanbanBoard {
        try mutateBoard(boardID) { try $0.renameLane(id: id, title: title) }
    }

    /// Reposiciona uma raia aberta (índice entre as abertas). A Done fica fixa no fim.
    @discardableResult
    public func moveLane(id: UUID, to index: Int, in boardID: UUID) throws -> KanbanBoard {
        try mutateBoard(boardID) { $0.moveOpenLane(id: id, to: index) }
    }

    /// Tarefas abertas do quadro que estão nesta raia — a UI pede confirmação antes de apagar.
    public func openTaskCount(inLane id: UUID, of boardID: UUID) throws -> Int {
        let board = try board(id: boardID)
        let all = try tasks.allTasks()
        return all.filter { !$0.isCompleted && board.includes($0, in: all) && board.lane(for: $0).id == id }.count
    }

    /// Apaga uma raia aberta. As tarefas abertas do quadro que ESTAVAM nela (pela mesma regra de
    /// `lane(for:)` que o quadro e a confirmação usam — inclui as sem raia gravada quando é a
    /// primeira) vão para a nova primeira raia com uma entrada de histórico; as demais só perdem
    /// a referência à raia apagada. Posições em outros quadros não mudam.
    ///
    /// Tarefas numa gravação só e ANTES do quadro: se a gravação das tarefas falhar, nada
    /// mudou; se a do quadro falhar depois, as tarefas já apontam para a raia destino (válida
    /// nos dois quadros) e a raia some na próxima tentativa.
    @discardableResult
    public func deleteLane(id: UUID, in boardID: UUID) throws -> KanbanBoard {
        let allBoards = try boards()
        guard let before = allBoards.first(where: { $0.id == boardID }) else { throw DomainError.boardNotFound }
        var after = before
        guard let removed = try after.removeLane(id: id) else { return before }

        let destination = after.firstOpenLane
        let text = historyPrefix(for: before, among: allBoards)
            + "Movida: \(removed.title) → \(destination.title) (raia removida)"
        let all = try tasks.allTasks()
        let updated = all.map { task -> FocusTask in
            var task = task
            if !task.isCompleted && before.includes(task, in: all) && before.lane(for: task).id == id {
                task.place(inLane: destination.id, of: before)
                task.history.append(TaskHistoryEntry(id: makeID(), createdAt: now(), text: text))
            } else {
                task.laneIDs.removeAll { $0 == id }
            }
            return task
        }
        if updated != all { try tasks.replaceAll(updated) }
        try save(after)
        return after
    }

    // MARK: - Movimentação

    /// Move a tarefa para outra raia do quadro — único ponto de movimentação do quadro.
    ///
    /// - Para a Done: conclui (com espelhamento no Lembretes) — em todos os quadros.
    /// - Saindo da Done: reabre e entra na raia destino deste quadro; nos outros quadros ela volta
    ///   à raia que tinha lá.
    /// - Entre raias abertas: só grava a raia deste quadro.
    ///
    /// Grava `"Movida: <origem> → <destino>"` no histórico (com o nome do quadro quando há mais de
    /// um). Mesma raia, tarefa ou raia inexistente: no-op. Devolve o resultado do espelhamento
    /// para a UI avisar falha.
    @discardableResult
    public func moveTask(id: UUID, toLane laneID: UUID, in boardID: UUID) async throws -> ReminderSyncOutcome {
        let allBoards = try boards()
        guard let board = allBoards.first(where: { $0.id == boardID }) else { throw DomainError.boardNotFound }
        var all = try tasks.allTasks()
        guard let idx = all.firstIndex(where: { $0.id == id }),
              let target = board.lane(id: laneID) else { return .notApplicable }
        let origin = board.lane(for: all[idx])
        guard origin.id != target.id else { return .notApplicable }

        // Conclusão/reabertura + raia + histórico numa gravação só; o espelhamento no Lembretes
        // vem depois, sobre o estado já gravado (best-effort, como na lista). Para a Done, a
        // conclusão é em cascata (FEAT-003): as subtarefas abertas fecham junto e, como a raia
        // é derivada da conclusão, os cartões delas vão para a Done também.
        let entry = TaskHistoryEntry(
            id: makeID(), createdAt: now(),
            text: historyPrefix(for: board, among: allBoards) + "Movida: \(origin.title) → \(target.title)")
        // Saindo da Done, uma subtarefa reabre também o pai concluído (invariante "subtarefa
        // ativa ⇒ pai ativo") — o cartão do pai volta à raia que ele tinha.
        var reopenedParent: FocusTask?
        var completion: ManageTasksUseCase.CompletionCascade?
        if target.isDone {
            completion = tasks.applyCompletionCascade(id: id, in: &all)
        } else if origin.isDone {
            reopenedParent = tasks.applyReopenCascade(id: id, in: &all)?.reopenedParent
        }
        all[idx].history.append(entry)
        if !target.isDone {
            all[idx].place(inLane: target.id, of: board)
        }
        // Concluída mantém as raias: reabrir pela lista a devolve às raias de antes. Diária
        // (FEAT-004) idem — o clone para amanhã que a cascata acrescentou nasce sem raia (1ª) e
        // leva o documento (FEAT-007) na mesma transação.
        try tasks.saveCompletion(all, cascade: completion)
        guard target.isDone || origin.isDone else { return .notApplicable }
        let outcome = await tasks.syncCompletion(of: all[idx])
        guard let reopenedParent else { return outcome }
        let parentOutcome = await tasks.syncCompletion(of: reopenedParent)
        if outcome == .failed || parentOutcome == .failed { return .failed }
        return outcome == .notApplicable ? parentOutcome : outcome
    }

    // MARK: - Helpers

    /// Com mais de um quadro, o histórico diz em qual a movimentação aconteceu ("Casa: Movida…");
    /// com um só, fica como era antes da FEAT-008.
    private func historyPrefix(for board: KanbanBoard, among all: [KanbanBoard]) -> String {
        all.count > 1 ? "\(board.name): " : ""
    }

    private func validName(_ name: String, excluding id: UUID?, in all: [KanbanBoard]) throws -> String {
        let valid = try KanbanBoard.validName(name)
        let clash = all.contains { $0.id != id && $0.name.caseInsensitiveCompare(valid) == .orderedSame }
        guard !clash else { throw DomainError.duplicateBoardName(valid) }
        return valid
    }

    private func mutateBoard(_ id: UUID, _ mutate: (inout KanbanBoard) throws -> Void) throws -> KanbanBoard {
        var board = try board(id: id)
        try mutate(&board)
        try save(board)
        return board
    }

    /// Substitui o quadro na lista e grava a lista inteira.
    private func save(_ board: KanbanBoard) throws {
        var all = try boards()
        guard let idx = all.firstIndex(where: { $0.id == board.id }) else { throw DomainError.boardNotFound }
        all[idx] = board
        try repository.saveBoards(all)
    }
}
