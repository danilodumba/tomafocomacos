import Foundation
import TomafocoDomain
import TomafocoApplication

/// Aba Kanban das Configurações (FEAT-005; vários quadros desde a FEAT-008): quadros (criar,
/// renomear, apagar) e, para o quadro selecionado, raias, dias no Done e quais tarefas entram
/// (escopo por tag e por projeto). Separado do `SettingsViewModel` (que é todo
/// `PomodoroConfiguration`) porque a configuração dos quadros mora no banco. Grava na hora,
/// como o resto das Configurações.
@MainActor
final class KanbanSettingsViewModel: ObservableObject {

    /// Raia aberta aguardando confirmação para ser apagada (tem tarefas).
    struct PendingDeletion: Identifiable {
        let lane: KanbanLane
        let openTaskCount: Int
        var id: UUID { lane.id }
    }

    /// Quadro aguardando confirmação para ser apagado.
    struct PendingBoardDeletion: Identifiable {
        let board: KanbanBoard
        let openTaskCount: Int
        var id: UUID { board.id }
    }

    @Published private(set) var boards: [KanbanBoard] = []
    @Published private(set) var board: KanbanBoard?
    @Published private(set) var knownTags: [String] = []
    @Published private(set) var projects: [Project] = []
    @Published var newLaneTitle = ""
    @Published var newBoardName = ""
    @Published var feedback: String?
    @Published var pendingDeletion: PendingDeletion?
    @Published var pendingBoardDeletion: PendingBoardDeletion?

    private let useCase: ManageKanbanUseCase
    private let manageTasks: ManageTasksUseCase
    private let manageProjects: ManageProjectsUseCase
    private let defaults: UserDefaults
    /// Os quadros mudaram — as janelas Kanban e os menus recarregam.
    private let onBoardChanged: () -> Void
    private var settingsBoardObserver: NSObjectProtocol?

    init(useCase: ManageKanbanUseCase, manageTasks: ManageTasksUseCase, manageProjects: ManageProjectsUseCase,
         defaults: UserDefaults = .standard, onBoardChanged: @escaping () -> Void) {
        self.useCase = useCase
        self.manageTasks = manageTasks
        self.manageProjects = manageProjects
        self.defaults = defaults
        self.onBoardChanged = onBoardChanged
        // Sem `reload()` aqui: a aba pode nunca ser aberta — a primeira leitura é no `onAppear`.
        // "Configurar quadro…" numa janela troca o quadro desta aba mesmo com ela já aberta.
        settingsBoardObserver = NotificationCenter.default.addObserver(
            forName: KanbanSettingsBoard.didChange, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reload() }
        }
        // Sem `removeObserver` no deinit: o VM vive o app inteiro (retido pelo `AppContainer`) e o
        // bloco segura `self` fraco.
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

    /// Relê quadros, tags e projetos — podem ter mudado em outra janela desde a última vez. O
    /// quadro selecionado é o gravado em `KanbanSettingsBoard` (o último configurado ou o da
    /// janela que pediu "Configurar quadro…"); apagado → o primeiro.
    func reload() {
        boards = (try? useCase.boards()) ?? []
        let selected = KanbanSettingsBoard.load(defaults: defaults)
        board = boards.first { $0.id == selected } ?? boards.first
        knownTags = (try? manageTasks.allTags()) ?? []
        projects = (try? manageProjects.allProjects()) ?? []
    }

    // MARK: - Quadros (FEAT-008)

    var selectedBoardID: UUID? { board?.id }

    func selectBoard(_ id: UUID) {
        feedback = nil
        KanbanSettingsBoard.save(id, defaults: defaults)  // a notificação relê
    }

    var canDeleteBoard: Bool { boards.count > 1 }

    func createBoard() {
        feedback = nil
        do {
            let created = try useCase.createBoard(name: newBoardName)
            newBoardName = ""
            KanbanSettingsBoard.save(created.id, defaults: defaults)
            onBoardChanged()
        } catch {
            feedback = message(for: error)
        }
    }

    /// Renomeia o quadro selecionado. Mesmo nome é no-op.
    func renameBoard(to name: String) {
        guard let board, name.trimmingCharacters(in: .whitespacesAndNewlines) != board.name else { return }
        apply { try self.useCase.renameBoard(id: board.id, name: name) }
    }

    /// Sempre pede confirmação: apagar quadro desfaz a organização das raias dele.
    func requestDeleteBoard() {
        feedback = nil
        guard let board else { return }
        let count = (try? useCase.openTaskCount(inBoard: board.id)) ?? 0
        pendingBoardDeletion = PendingBoardDeletion(board: board, openTaskCount: count)
    }

    func confirmBoardDeletion() {
        guard let pending = pendingBoardDeletion else { return }
        pendingBoardDeletion = nil
        do {
            try useCase.deleteBoard(id: pending.board.id)
            reload()
            onBoardChanged()
        } catch {
            feedback = message(for: error)
        }
    }

    // MARK: - Concluídas

    var doneRetentionDays: Int { board?.doneRetentionDays ?? KanbanBoard.defaultDoneRetentionDays }

    func setDoneRetentionDays(_ days: Int) {
        guard let id = board?.id else { return }
        apply { try self.useCase.setDoneRetentionDays(days, in: id) }
    }

    // MARK: - Tarefas no quadro

    // Regras de edição do escopo moram em `TaskScope` (Domain) — a aba Pomodoro usa as mesmas.
    private var scope: TaskScope { board?.taskScope ?? .all }

    var scopeIsByTag: Bool { scope.isByTag }
    var selectableTags: [String] { scope.selectableTags(knownTags: knownTags) }
    func isSelected(_ tag: String) -> Bool { scope.contains(tag) }

    func setScopeByTag(_ byTag: Bool) {
        guard let id = board?.id, let next = scope.switchingByTag(byTag) else { return }
        apply { try self.useCase.setTaskScope(next, in: id) }
    }

    func setTag(_ tag: String, selected: Bool) {
        guard let id = board?.id else { return }
        let next = scope.settingTag(tag, selected: selected)
        apply { try self.useCase.setTaskScope(next, in: id) }
    }

    /// Escopo por projeto (FEAT-008). Projeto apagado que ainda esteja no escopo aparece como
    /// opção própria até o usuário trocar — mas apagar projeto já volta o escopo a "todos".
    var projectScope: ProjectFilter { board?.projectScope ?? .all }

    func setProjectScope(_ scope: ProjectFilter) {
        guard let id = board?.id, scope != projectScope else { return }
        apply { try self.useCase.setProjectScope(scope, in: id) }
    }

    // MARK: - Raias

    func addLane() {
        guard let id = board?.id else { return }
        apply { try self.useCase.addLane(title: self.newLaneTitle, in: id) }
        if feedback == nil { newLaneTitle = "" }
    }

    func renameLane(_ lane: KanbanLane, to title: String) {
        guard let id = board?.id, title.trimmingCharacters(in: .whitespacesAndNewlines) != lane.title else { return }
        apply { try self.useCase.renameLane(id: lane.id, title: title, in: id) }
    }

    /// Sobe (-1) ou desce (+1) uma raia aberta. A Done não se move.
    func moveLane(_ lane: KanbanLane, by offset: Int) {
        guard let id = board?.id,
              let index = board?.openLanes.firstIndex(where: { $0.id == lane.id }) else { return }
        apply { try self.useCase.moveLane(id: lane.id, to: index + offset, in: id) }
    }

    /// Raia vazia sai na hora; com tarefas abertas, pede confirmação antes.
    func requestDelete(_ lane: KanbanLane) {
        feedback = nil
        guard let id = board?.id else { return }
        let count = (try? useCase.openTaskCount(inLane: lane.id, of: id)) ?? 0
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
        guard let id = board?.id else { return }
        apply { try self.useCase.deleteLane(id: lane.id, in: id) }
    }

    // MARK: - Helpers

    private func apply(_ change: () throws -> KanbanBoard) {
        feedback = nil
        do {
            let changed = try change()
            board = changed
            if let idx = boards.firstIndex(where: { $0.id == changed.id }) { boards[idx] = changed }
            onBoardChanged()
        } catch {
            feedback = message(for: error)
            // Quadro apagado em outra janela: relê para a aba não ficar mostrando um fantasma.
            if case DomainError.boardNotFound = error { reload() }
        }
    }

    private func message(for error: Error) -> String {
        switch error {
        case DomainError.emptyLaneTitle: return "Informe um nome para a raia."
        case DomainError.cannotDeleteDoneLane: return "A raia de concluídas não pode ser apagada."
        case DomainError.cannotDeleteLastOpenLane:
            return "O quadro precisa de pelo menos uma raia além da de concluídas."
        case DomainError.emptyBoardName: return "Informe um nome para o quadro."
        case DomainError.duplicateBoardName(let name): return "Já existe um quadro chamado \"\(name)\"."
        case DomainError.cannotDeleteLastBoard: return "É preciso ter pelo menos um quadro."
        case DomainError.boardNotFound: return "Este quadro foi apagado em outra janela."
        default: return "Não foi possível salvar: \(error.localizedDescription)"
        }
    }
}
