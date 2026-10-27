import Foundation
import TomafocoDomain
import TomafocoApplication

/// Aba Kanban das Configurações (FEAT-005): raias, dias no Done e quais tarefas entram no
/// quadro (escopo por tag). Separado do `SettingsViewModel` (que é todo `PomodoroConfiguration`)
/// porque a configuração do quadro mora no `kanban.json`. Grava na hora, como o resto das
/// Configurações.
@MainActor
final class KanbanSettingsViewModel: ObservableObject {

    /// Raia aberta aguardando confirmação para ser apagada (tem tarefas).
    struct PendingDeletion: Identifiable {
        let lane: KanbanLane
        let openTaskCount: Int
        var id: UUID { lane.id }
    }

    @Published private(set) var board: KanbanBoard?
    @Published private(set) var knownTags: [String] = []
    @Published var newLaneTitle = ""
    @Published var feedback: String?
    @Published var pendingDeletion: PendingDeletion?

    private let useCase: ManageKanbanUseCase
    private let manageTasks: ManageTasksUseCase
    /// O quadro mudou — a janela Kanban recarrega.
    private let onBoardChanged: () -> Void

    init(useCase: ManageKanbanUseCase, manageTasks: ManageTasksUseCase,
         onBoardChanged: @escaping () -> Void) {
        self.useCase = useCase
        self.manageTasks = manageTasks
        self.onBoardChanged = onBoardChanged
        // Sem `reload()` aqui: a aba pode nunca ser aberta — a primeira leitura é no `onAppear`.
    }

    /// A aba está na tela; fora dela o relay não manda `reload()`.
    private(set) var isPresented = false

    func didAppear() {
        isPresented = true
        reload()
    }

    func didDisappear() {
        isPresented = false
    }

    /// Relê quadro e tags — tags podem ter sido criadas na janela Tarefas desde a última vez.
    func reload() {
        board = try? useCase.board()
        knownTags = (try? manageTasks.allTags()) ?? []
    }

    // MARK: - Concluídas

    var doneRetentionDays: Int { board?.doneRetentionDays ?? KanbanBoard.defaultDoneRetentionDays }

    func setDoneRetentionDays(_ days: Int) {
        apply { try self.useCase.setDoneRetentionDays(days) }
    }

    // MARK: - Tarefas no quadro

    // Regras de edição do escopo moram em `TaskScope` (Domain) — a aba Pomodoro usa as mesmas.
    private var scope: TaskScope { board?.taskScope ?? .all }

    var scopeIsByTag: Bool { scope.isByTag }
    var selectableTags: [String] { scope.selectableTags(knownTags: knownTags) }
    func isSelected(_ tag: String) -> Bool { scope.contains(tag) }

    func setScopeByTag(_ byTag: Bool) {
        guard let next = scope.switchingByTag(byTag) else { return }
        apply { try self.useCase.setTaskScope(next) }
    }

    func setTag(_ tag: String, selected: Bool) {
        let next = scope.settingTag(tag, selected: selected)
        apply { try self.useCase.setTaskScope(next) }
    }

    // MARK: - Raias

    func addLane() {
        apply { try self.useCase.addLane(title: self.newLaneTitle) }
        if feedback == nil { newLaneTitle = "" }
    }

    func renameLane(_ lane: KanbanLane, to title: String) {
        guard title.trimmingCharacters(in: .whitespacesAndNewlines) != lane.title else { return }
        apply { try self.useCase.renameLane(id: lane.id, title: title) }
    }

    /// Sobe (-1) ou desce (+1) uma raia aberta. A Done não se move.
    func moveLane(_ lane: KanbanLane, by offset: Int) {
        guard let index = board?.openLanes.firstIndex(where: { $0.id == lane.id }) else { return }
        apply { try self.useCase.moveLane(id: lane.id, to: index + offset) }
    }

    /// Raia vazia sai na hora; com tarefas abertas, pede confirmação antes.
    func requestDelete(_ lane: KanbanLane) {
        feedback = nil
        let count = (try? useCase.openTaskCount(inLane: lane.id)) ?? 0
        if count == 0 {
            delete(lane)
        } else {
            pendingDeletion = PendingDeletion(lane: lane, openTaskCount: count)
        }
    }

    func confirmPendingDeletion() {
        guard let pending = pendingDeletion else { return }
        pendingDeletion = nil
        delete(pending.lane)
    }

    var firstOpenLaneTitle: String { board?.firstOpenLane.title ?? "A fazer" }

    func canDelete(_ lane: KanbanLane) -> Bool {
        !lane.isDone && (board?.openLanes.count ?? 0) > 1
    }

    private func delete(_ lane: KanbanLane) {
        apply { try self.useCase.deleteLane(id: lane.id) }
    }

    // MARK: - Helpers

    private func apply(_ change: () throws -> KanbanBoard) {
        feedback = nil
        do {
            board = try change()
            onBoardChanged()
        } catch DomainError.emptyLaneTitle {
            feedback = "Informe um nome para a raia."
        } catch DomainError.cannotDeleteDoneLane {
            feedback = "A raia de concluídas não pode ser apagada."
        } catch DomainError.cannotDeleteLastOpenLane {
            feedback = "O quadro precisa de pelo menos uma raia além da de concluídas."
        } catch {
            feedback = "Não foi possível salvar: \(error.localizedDescription)"
        }
    }
}
