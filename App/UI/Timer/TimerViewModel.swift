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
    @Published private(set) var isAwaitingNextFocus = false
    /// Fração já decorrida da fase atual (0…1) — alimenta o anel de progresso.
    @Published private(set) var progress: Double = 0
    /// Fase corrente, usada só para escolher o acento visual.
    @Published private(set) var phase: SessionPhase = .idle
    /// `true` sempre que existe uma fase corrente para pular (qualquer estado exceto ocioso).
    @Published private(set) var canSkip = false
    @Published var reason = ""
    @Published var errorMessage: String?
    @Published var pendingRecovery: PomodoroSession?

    /// Rótulo curto para o item da barra de menus.
    @Published private(set) var menuBarLabel = "🍅"

    private let coordinator: SessionCoordinator
    private let settings: SettingsRepository
    private var recover: RecoverFromCrashUseCase?

    var requiresReason: Bool {
        let hc = settings.loadConfiguration().hardcore
        return hc.isEnabled && hc.requireReason
    }

    init(coordinator: SessionCoordinator, settings: SettingsRepository) {
        self.coordinator = coordinator
        self.settings = settings
        coordinator.onStateChange = { [weak self] state in self?.render(state) }
        render(coordinator.state)
    }

    // MARK: - Ações

    func startFocus() async {
        errorMessage = nil
        do {
            try await coordinator.startFocus(reason: reason.isEmpty ? nil : reason)
            reason = ""
        } catch DomainError.reasonRequired {
            errorMessage = "Informe um motivo para iniciar o foco (modo hardcore)."
        } catch {
            errorMessage = "Não foi possível iniciar: \(error.localizedDescription)"
        }
    }

    func pause() async { await coordinator.pause() }
    func resume() async { await coordinator.resume() }
    func beginNextFocus() async { await coordinator.beginNextFocus() }

    /// SKIP: pula a fase corrente — foco vai para o intervalo, intervalo vai para o próximo foco (RF-04.2).
    func skip() async {
        errorMessage = nil
        guard !isAwaitingNextFocus else { return await coordinator.beginNextFocus() }
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

    private func render(_ state: SessionMachineState) {
        isIdle = false
        isRunning = false
        isPaused = false
        isAwaitingNextFocus = false

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

        case .awaitingNextFocus(let nextCycle):
            isAwaitingNextFocus = true
            phase = .idle
            phaseTitle = "Intervalo concluído"
            cycleText = "Próximo: ciclo \(nextCycle)"
            timeText = format(settings.loadConfiguration().focusDuration)
            progress = 0
            canSkip = true
            menuBarLabel = "▶️"
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
