import Foundation
import SwiftUI
import TomafocoDomain
import TomafocoApplication

/// ViewModel da janela/menu bar do timer. Deriva TODA a UI do estado do `SessionCoordinator`
/// (fonte única). Não conhece adapters — só o coordinator e o repositório de settings.
@MainActor
final class TimerViewModel: ObservableObject {

    @Published private(set) var phaseTitle = "Pronto"
    @Published private(set) var timeText = "25:00"
    @Published private(set) var cycleText = ""
    @Published private(set) var isRunning = false
    @Published private(set) var isPaused = false
    @Published private(set) var isIdle = true
    @Published private(set) var isAwaitingNext = false
    /// Fração já decorrida da fase atual (0…1) — alimenta o anel de progresso.
    @Published private(set) var progress: Double = 0
    /// Fase corrente, usada só para escolher o acento visual.
    @Published private(set) var phase: SessionPhase = .idle
    /// `true` sempre que existe uma fase corrente para pular (qualquer estado exceto ocioso).
    @Published private(set) var canSkip = false
    @Published var errorMessage: String?
    @Published var pendingRecovery: PomodoroSession?

    /// Tarefas escolhidas para o próximo foco (RF-09/RF-09.4). Vazio = focar sem tarefa.
    /// Com o foco multi-tarefa desligado, no máximo uma entra aqui.
    @Published var selectedTaskIDs: Set<UUID> = []
    /// Tarefas vinculadas à sessão corrente (running/paused). Espelha `session.taskIDs` e é a
    /// seleção do picker exibido quando o foco está pausado (RF-09.1 — trocar tarefa no meio).
    @Published private(set) var currentSessionTaskIDs: Set<UUID> = []
    /// Tarefas disponíveis no seletor — recarregadas sempre que o timer fica ocioso.
    @Published private(set) var availableTasks: [FocusTask] = []
    /// Título(s) da(s) tarefa(s) da sessão corrente — visível no anel durante toda a sessão,
    /// para o usuário nunca perder de vista no que deveria estar focando.
    @Published private(set) var currentTaskTitle: String?

    /// Permite escolher mais de uma tarefa por foco (lido da config a cada acesso).
    var allowsMultipleTasks: Bool { settings.loadConfiguration().allowMultipleTasksInFocus }

    /// Último título resolvido, por conjunto de tarefas. Evita ir ao disco a cada tick (1/s) e
    /// preserva o título caso a tarefa seja apagada/concluída no meio da sessão.
    private var resolvedTaskTitle: (key: String, title: String)?

    /// Tempo mostrado ao lado do tomate na barra de menus. Vazio quando ocioso — aí só o
    /// ícone aparece, sem número solto.
    @Published private(set) var menuBarLabel = ""
    /// SF Symbol de estado ao lado do tempo (pausado / aguardando confirmação), ou `nil`.
    @Published private(set) var menuBarSymbol: String?
    /// `true` quando a tela cheia de intervalo deve estar visível (RF-01.3).
    @Published private(set) var showsBreakOverlay = false

    /// Chave do intervalo cuja tela o usuário dispensou. Guardada por intervalo para que
    /// fechar a tela de um não esconda a do próximo.
    private var dismissedOverlayKey: String?

    private let coordinator: SessionCoordinator
    private let settings: SettingsRepository
    private let manageTasks: ManageTasksUseCase
    private var recover: RecoverFromCrashUseCase?

    init(coordinator: SessionCoordinator, settings: SettingsRepository, manageTasks: ManageTasksUseCase) {
        self.coordinator = coordinator
        self.settings = settings
        self.manageTasks = manageTasks
        coordinator.onStateChange = { [weak self] state in self?.render(state) }
        render(coordinator.state)
    }

    // MARK: - Ações

    func startFocus() async {
        errorMessage = nil
        await coordinator.startFocus(taskIDs: Array(selectedTaskIDs))
    }

    func pause() async {
        await coordinator.pause()
        // Só o foco pausado mostra o seletor; carrega a lista fresca uma vez por pausa
        // (não a cada tick — pausado ainda dispara render 1/s).
        if isPaused { reloadAvailableTasks() }
    }
    func resume() async { await coordinator.resume() }

    /// RF-09.1 — troca as tarefas da sessão pausada (usuário finalizou/mudou de tarefa no meio do foco).
    func changeCurrentTasks(_ taskIDs: Set<UUID>) async {
        await coordinator.changeTask(Array(taskIDs))
    }

    /// Alterna uma tarefa na seleção do PRÓXIMO foco. Modo tarefa única substitui; multi alterna.
    func toggleSelectedTask(_ id: UUID) {
        if allowsMultipleTasks {
            if selectedTaskIDs.contains(id) { selectedTaskIDs.remove(id) } else { selectedTaskIDs.insert(id) }
        } else {
            selectedTaskIDs = selectedTaskIDs.contains(id) ? [] : [id]
        }
    }

    /// Alterna uma tarefa na sessão PAUSADA. Mesma regra única/múltipla.
    func toggleCurrentTask(_ id: UUID) async {
        var ids = currentSessionTaskIDs
        if allowsMultipleTasks {
            if ids.contains(id) { ids.remove(id) } else { ids.insert(id) }
        } else {
            ids = ids.contains(id) ? [] : [id]
        }
        await changeCurrentTasks(ids)
    }
    func beginNextPhase() async { await coordinator.beginNextPhase() }

    /// SKIP: pula a fase corrente — foco vai para o intervalo, intervalo vai para o próximo foco (RF-04.2).
    func skip() async {
        errorMessage = nil
        guard !isAwaitingNext else { return await coordinator.beginNextPhase() }
        await coordinator.skipPhase()
    }

    func cancel() async {
        errorMessage = nil
        await coordinator.cancel()
    }

    // MARK: - Recuperação pós-crash (UC-04)

    func handleRecovery(_ result: RecoverFromCrashUseCase.Result, recover: RecoverFromCrashUseCase) {
        self.recover = recover
        if case .pendingActiveSession(let session) = result {
            pendingRecovery = session
        }
    }

    /// Retoma a sessão pendente de onde ela parou (T-21). O tempo perdido no crash não volta:
    /// a sessão guarda término absoluto, então pode expirar no primeiro tick — e isso é correto.
    func resumeRecoveredSession() async {
        guard let session = pendingRecovery else { return }
        pendingRecovery = nil
        await coordinator.adoptRecoveredSession(session)
    }

    func discardRecoveredSession() async {
        await recover?.discardPendingSession()
        pendingRecovery = nil
    }

    /// Descrição da sessão recuperada para o diálogo (fase, ciclo e quanto falta).
    func recoveryDescription(for session: PomodoroSession) -> String {
        let remaining = format(session.remaining(now: Date()))
        return "\(title(for: session.phase)) · ciclo \(session.cycleNumber) · faltam \(remaining)"
    }

    // MARK: - Render

    /// Fecha a tela cheia do intervalo atual. O próximo intervalo volta a exibi-la.
    func dismissBreakOverlay() {
        dismissedOverlayKey = BreakOverlayPolicy.presentationKey(for: coordinator.state)
        showsBreakOverlay = false
    }

    private func render(_ state: SessionMachineState) {
        isIdle = false
        isRunning = false
        isPaused = false
        isAwaitingNext = false

        let overlayKey = BreakOverlayPolicy.presentationKey(for: state)
        showsBreakOverlay = overlayKey != nil && overlayKey != dismissedOverlayKey

        currentTaskTitle = resolveTaskTitle(for: state)
        currentSessionTaskIDs = Set(state.currentSession?.taskIDs ?? [])

        switch state {
        case .idle:
            isIdle = true
            phase = .idle
            phaseTitle = "Pronto para focar"
            cycleText = ""
            timeText = format(settings.loadConfiguration().focusDuration)
            progress = 0
            canSkip = false
            menuBarLabel = ""
            menuBarSymbol = nil
            reloadAvailableTasks()

        case .running(let session):
            isRunning = true
            phase = session.phase
            phaseTitle = title(for: session.phase)
            cycleText = "Ciclo \(session.cycleNumber)"
            let remaining = session.remaining(now: Date())
            timeText = format(remaining)
            progress = fraction(remaining: remaining, of: session)
            canSkip = true
            menuBarLabel = format(remaining)
            menuBarSymbol = nil

        case .paused(let session, let remaining):
            isPaused = true
            phase = session.phase
            phaseTitle = "Pausado — \(title(for: session.phase))"
            cycleText = "Ciclo \(session.cycleNumber)"
            timeText = format(remaining)
            progress = fraction(remaining: remaining, of: session)
            canSkip = true
            menuBarLabel = format(remaining)
            menuBarSymbol = "pause.fill"

        case .awaitingNext(let next, let cycle, _):
            isAwaitingNext = true
            // Mostra a fase que VAI começar: o anel e o botão já aparecem na cor dela.
            phase = next
            phaseTitle = "\(title(for: next)) em espera"
            cycleText = next == .focus ? "Próximo: ciclo \(cycle)" : "Ciclo \(cycle)"
            timeText = format(settings.loadConfiguration().duration(for: next))
            progress = 0
            canSkip = false
            menuBarLabel = format(settings.loadConfiguration().duration(for: next))
            menuBarSymbol = "play.fill"
        }
    }

    /// Título(s) da(s) tarefa(s) vinculada(s) ao estado corrente. Ocioso mostra a SELEÇÃO (o
    /// picker já exibe, então devolve `nil`); nos demais estados, as tarefas que atravessam o ciclo.
    private func resolveTaskTitle(for state: SessionMachineState) -> String? {
        let taskIDs: [UUID]
        switch state {
        case .idle: taskIDs = []
        case .running(let session), .paused(let session, _): taskIDs = session.taskIDs
        case .awaitingNext(_, _, let ids): taskIDs = ids
        }
        guard !taskIDs.isEmpty else {
            resolvedTaskTitle = nil
            return nil
        }
        let key = taskIDs.map(\.uuidString).sorted().joined(separator: ",")
        if let cached = resolvedTaskTitle, cached.key == key { return cached.title }

        // Fora do cache: procura nas ativas já carregadas e, em último caso, no disco
        // (uma vez por conjunto — o cache segura os ticks seguintes).
        let all = availableTasks + ((try? manageTasks.allTasks()) ?? [])
        let titles = taskIDs.compactMap { id in all.first { $0.id == id }?.title }
        guard !titles.isEmpty else { return nil }
        let title = joinedTitle(titles)
        resolvedTaskTitle = (key, title)
        return title
    }

    /// Junta os títulos das tarefas do foco: "A", "A, B" ou "A, B +2" para não estourar o anel.
    private func joinedTitle(_ titles: [String]) -> String {
        guard titles.count > 2 else { return titles.joined(separator: ", ") }
        return titles.prefix(2).joined(separator: ", ") + " +\(titles.count - 2)"
    }

    /// Recarrega o seletor de tarefas. Chamado ao ficar ocioso e pela janela de tarefas
    /// após qualquer mudança (criar/concluir/importar) — seleção morta é limpa.
    func reloadAvailableTasks() {
        availableTasks = (try? manageTasks.activeTasks()) ?? []
        let live = Set(availableTasks.map(\.id))
        selectedTaskIDs.formIntersection(live)
    }

    /// Fração decorrida da fase — 0 no início, 1 no fim.
    private func fraction(remaining: TimeInterval, of session: PomodoroSession) -> Double {
        let planned = session.plannedDuration
        guard planned > 0 else { return 0 }
        return min(max(1 - remaining / planned, 0), 1)
    }

    private func title(for phase: SessionPhase) -> String {
        switch phase {
        case .focus: return "Foco"
        case .shortBreak: return "Intervalo curto"
        case .longBreak: return "Intervalo longo"
        case .idle: return "Pronto"
        }
    }

    private func format(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
