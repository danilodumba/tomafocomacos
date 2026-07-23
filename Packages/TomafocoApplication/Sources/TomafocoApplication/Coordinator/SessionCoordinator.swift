import Foundation
import os
import TomafocoDomain

/// Orquestrador de runtime da sessão Pomodoro. É a fachada que a camada de apresentação usa.
///
/// Fonte única de verdade do estado: mantém o `SessionMachineState`, alimenta a máquina pura
/// com eventos (injetando `now` e novos `UUID`s) e INTERPRETA os `SessionEffect`s chamando os
/// ports. Concentra aqui os "casos de uso" de start/pause/resume/cancel/next (SRP por método),
/// deixando a decisão de transição na máquina pura e a validação hardcore na `HardcoreCancelPolicy`.
///
/// `@MainActor`: todo o ciclo de vida roda na main; o clock de Infrastructure entrega ticks na main.
@MainActor
public final class SessionCoordinator {

    public private(set) var state: SessionMachineState = .idle {
        didSet { onStateChange?(state) }
    }

    /// Observado pela apresentação para redesenhar (evita acoplar Application a Combine/SwiftUI).
    public var onStateChange: ((SessionMachineState) -> Void)?

    /// Indica que o último `activateBlocking` falhou ao bloquear sites (UC-01, fluxo 4a).
    public private(set) var websiteBlockingUnavailable = false

    private let clock: SessionClock
    private let appBlocker: AppBlocking
    private let websiteBlocker: WebsiteBlocking
    private let sessions: SessionRepository
    private let settings: SettingsRepository
    private let notifier: UserNotifying
    private let makeID: () -> UUID

    /// Falha de persistência não interrompe a sessão (o timer é mais importante que o snapshot),
    /// mas jamais pode ser silenciosa: sem log, um failsafe morto (RNF-02) só aparece no crash.
    private static let logger = Logger(subsystem: "com.dsdumba.tomafoco", category: "SessionCoordinator")

    private var subscription: ClockSubscription?

    public init(
        clock: SessionClock,
        appBlocker: AppBlocking,
        websiteBlocker: WebsiteBlocking,
        sessions: SessionRepository,
        settings: SettingsRepository,
        notifier: UserNotifying,
        makeID: @escaping () -> UUID = { UUID() }
    ) {
        self.clock = clock
        self.appBlocker = appBlocker
        self.websiteBlocker = websiteBlocker
        self.sessions = sessions
        self.settings = settings
        self.notifier = notifier
        self.makeID = makeID
    }

    // MARK: - Casos de uso expostos

    /// UC-01 — inicia uma sessão de foco, opcionalmente vinculada a uma tarefa (RF-09).
    /// Valida a exigência de motivo do modo hardcore (RF-06.2).
    public func startFocus(reason: String?, taskID: UUID? = nil) async throws {
        let config = settings.loadConfiguration()
        if config.hardcore.isEnabled, config.hardcore.requireReason {
            let trimmed = reason?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !trimmed.isEmpty else { throw DomainError.reasonRequired }
        }
        await dispatch(.startFocus(reason: reason, taskID: taskID))
        ensureTicking()
    }

    /// RF-01.1 — pausa a sessão corrente (bloqueio permanece ativo durante a pausa do foco).
    public func pause() async { await dispatch(.pause) }

    /// RF-01.1 — retoma, recalculando o término absoluto a partir do tempo restante.
    public func resume() async {
        await dispatch(.resume)
        ensureTicking()
    }

    /// UC-03 — cancela a sessão, aplicando a política hardcore quando houver foco ativo.
    public func cancel() async throws {
        if let session = state.currentSession {
            let config = settings.loadConfiguration()
            if case .failure(let error) = HardcoreCancelPolicy.validate(session: session, config: config, now: clock.now) {
                throw error
            }
        }
        await dispatch(.cancel)
    }

    /// RF-04.2 — pula a fase corrente: foco vai direto para o intervalo, intervalo para o próximo foco.
    /// Pular o foco encerra o bloqueio antes da hora, então passa pela mesma política do
    /// cancelamento (RF-06.1) — do contrário o modo hardcore seria contornável pelo botão SKIP.
    public func skipPhase() async throws {
        if let session = state.currentSession {
            let config = settings.loadConfiguration()
            if case .failure(let error) = HardcoreCancelPolicy.validate(session: session, config: config, now: clock.now) {
                throw error
            }
        }
        await dispatch(.skipPhase)
        ensureTicking()
    }

    /// UC-04 — readota a sessão recuperada após crash/reinício, reativando os bloqueios.
    /// O `endsAt` original é preservado: o relógio não "para" durante o crash.
    public func adoptRecoveredSession(_ session: PomodoroSession) async {
        await dispatch(.adoptRecovered(session))
        ensureTicking()
    }

    /// RF-01.4 — confirma o início da próxima etapa quando o avanço automático está desligado.
    public func beginNextPhase() async {
        await dispatch(.beginNextPhase)
        ensureTicking()
    }

    // MARK: - Núcleo

    private func dispatch(_ event: SessionEvent) async {
        let (newState, effects) = SessionStateMachine.reduce(
            state: state, event: event,
            config: settings.loadConfiguration(),
            now: clock.now, newID: makeID()
        )
        state = newState
        await execute(effects)
        if case .idle = state { stopTicking() }
    }

    private func execute(_ effects: [SessionEffect]) async {
        for effect in effects {
            switch effect {
            case .activateBlocking:
                await activateBlocking()
            case .deactivateBlocking:
                appBlocker.deactivate()
                do { try await websiteBlocker.deactivate() } catch {
                    Self.logger.error("Falha ao desativar bloqueio de sites: \(String(describing: error), privacy: .public)")
                }
            case .persistActive(let session):
                do { try sessions.saveActive(session) } catch {
                    Self.logger.error("Falha ao persistir sessão ativa (failsafe RNF-02): \(String(describing: error), privacy: .public)")
                }
            case .clearActive:
                do { try sessions.clearActive() } catch {
                    Self.logger.error("Falha ao limpar sessão ativa: \(String(describing: error), privacy: .public)")
                }
            case .recordHistory(let record):
                do { try sessions.appendToHistory(record) } catch {
                    Self.logger.error("Falha ao gravar histórico: \(String(describing: error), privacy: .public)")
                }
            case .notify(let event):
                notifier.notify(event)
            }
        }
    }

    private func activateBlocking() async {
        let list = settings.loadBlockList()
        appBlocker.activate(blockedBundleIDs: list.activeAppBundleIDs)
        do {
            try await websiteBlocker.activate(domains: list.activeDomains)
            websiteBlockingUnavailable = false
        } catch {
            websiteBlockingUnavailable = true
            notifier.notify(.websiteBlockingUnavailable)
        }
    }

    // MARK: - Clock

    private func ensureTicking() {
        guard subscription == nil else { return }
        subscription = clock.schedule(every: 1) { [weak self] in
            Task { @MainActor in await self?.dispatch(.tick) }
        }
    }

    private func stopTicking() {
        subscription?.cancel()
        subscription = nil
    }
}
