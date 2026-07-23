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
    @Published var reason = ""
    @Published var errorMessage: String?
    @Published var pendingRecovery: PomodoroSession?

    /// Tarefa escolhida para o próximo foco (RF-09). `nil` = focar sem tarefa.
    @Published var selectedTaskID: UUID?
    /// Tarefas disponíveis no seletor — recarregadas sempre que o timer fica ocioso.
    @Published private(set) var availableTasks: [FocusTask] = []
    /// Título da tarefa da sessão corrente — visível no anel durante toda a sessão,
    /// para o usuário nunca perder de vista no que deveria estar focando.
    @Published private(set) var currentTaskTitle: String?

    /// Último título resolvido, por tarefa. Evita ir ao disco a cada tick (1/s) e preserva
    /// o título caso a tarefa seja apagada/concluída no meio da sessão.
    private var resolvedTaskTitle: (id: UUID, title: String)?

    /// Rótulo curto para o item da barra de menus.
    @Published private(set) var menuBarLabel = "🍅"
    /// `true` quando a tela cheia de intervalo deve estar visível (RF-01.3).
    @Published private(set) var showsBreakOverlay = false

    /// Chave do intervalo cuja tela o usuário dispensou. Guardada por intervalo para que
    /// fechar a tela de um não esconda a do próximo.
    private var dismissedOverlayKey: String?

    private let coordinator: SessionCoordinator
    private let settings: SettingsRepository
    private let manageTasks: ManageTasksUseCase
    private var recover: RecoverFromCrashUseCase?

    var requiresReason: Bool {
        let hc = settings.loadConfiguration().hardcore
        return hc.isEnabled && hc.requireReason
    }

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
        do {
            try await coordinator.startFocus(
                reason: reason.isEmpty ? nil : reason, taskID: selectedTaskID)
            reason = ""
        } catch DomainError.reasonRequired {
            errorMessage = "Informe um motivo para iniciar o foco (modo hardcore)."
        } catch {
            errorMessage = "Não foi possível iniciar: \(error.localizedDescription)"
        }
    }

    func pause() async { await coordinator.pause() }
    func resume() async { await coordinator.resume() }
    func beginNextPhase() async { await coordinator.beginNextPhase() }

    /// SKIP: pula a fase corrente — foco vai para o intervalo, intervalo vai para o próximo foco (RF-04.2).
    func skip() async {
        errorMessage = nil
        guard !isAwaitingNext else { return await coordinator.beginNextPhase() }
        do {
            try await coordinator.skipPhase()
        } catch DomainError.cancellationBlockedByHardcore(let remaining) {
            errorMessage = "Modo hardcore: aguarde \(remaining)s antes de pular o foco."
        } catch {
            errorMessage = "Não foi possível pular: \(error.localizedDescription)"
        }
    }

    func cancel() async {
        errorMessage = nil
        do {
            try await coordinator.cancel()
        } catch DomainError.cancellationBlockedByHardcore(let remaining) {
            errorMessage = "Modo hardcore: aguarde \(remaining)s antes de cancelar."
        } catch {
            errorMessage = "Não foi possível cancelar: \(error.localizedDescription)"
        }
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

        switch state {
        case .idle:
            isIdle = true
            phase = .idle
            phaseTitle = "Pronto para focar"
            cycleText = ""
            timeText = format(settings.loadConfiguration().focusDuration)
            progress = 0
            canSkip = false
            menuBarLabel = "🍅"
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
            menuBarLabel = "\(iconEmoji(for: session.phase)) \(format(remaining))"

        case .paused(let session, let remaining):
            isPaused = true
            phase = session.phase
            phaseTitle = "Pausado — \(title(for: session.phase))"
            cycleText = "Ciclo \(session.cycleNumber)"
            timeText = format(remaining)
            progress = fraction(remaining: remaining, of: session)
            canSkip = true
            menuBarLabel = "⏸ \(format(remaining))"

        case .awaitingNext(let next, let cycle, _):
            isAwaitingNext = true
            // Mostra a fase que VAI começar: o anel e o botão já aparecem na cor dela.
            phase = next
            phaseTitle = "\(title(for: next)) em espera"
            cycleText = next == .focus ? "Próximo: ciclo \(cycle)" : "Ciclo \(cycle)"
            timeText = format(settings.loadConfiguration().duration(for: next))
            progress = 0
            canSkip = false
            menuBarLabel = "▶️ \(format(settings.loadConfiguration().duration(for: next)))"
        }
    }

    /// Título da tarefa vinculada ao estado corrente. Ocioso mostra a SELEÇÃO (o picker já
    /// exibe, então devolve `nil`); nos demais estados, a tarefa que atravessa o ciclo.
    private func resolveTaskTitle(for state: SessionMachineState) -> String? {
        let taskID: UUID?
        switch state {
        case .idle: taskID = nil
        case .running(let session), .paused(let session, _): taskID = session.taskID
        case .awaitingNext(_, _, let id): taskID = id
        }
        guard let taskID else {
            resolvedTaskTitle = nil
            return nil
        }
        if let cached = resolvedTaskTitle, cached.id == taskID { return cached.title }

        // Fora do cache: procura nas ativas já carregadas e, em último caso, no disco
        // (uma vez por sessão — o cache segura os ticks seguintes).
        let title = availableTasks.first { $0.id == taskID }?.title
            ?? (try? manageTasks.allTasks())?.first { $0.id == taskID }?.title
        if let title { resolvedTaskTitle = (taskID, title) }
        return title
    }

    /// Recarrega o seletor de tarefas. Chamado ao ficar ocioso e pela janela de tarefas
    /// após qualquer mudança (criar/concluir/importar) — a seleção morta é limpa.
    func reloadAvailableTasks() {
        availableTasks = (try? manageTasks.activeTasks()) ?? []
        if let selected = selectedTaskID, !availableTasks.contains(where: { $0.id == selected }) {
            selectedTaskID = nil
        }
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

    private func iconEmoji(for phase: SessionPhase) -> String {
        phase == .focus ? "🍅" : "☕️"
    }

    private func format(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
