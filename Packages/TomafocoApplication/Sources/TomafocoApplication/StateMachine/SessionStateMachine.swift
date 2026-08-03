import Foundation
import TomafocoDomain

/// Máquina de estados PURA do Pomodoro.
///
/// `reduce` é uma função sem efeitos colaterais: dado `(estado, evento, config, now, newID)`
/// devolve `(novoEstado, [efeito])`. Todo I/O (bloqueio, persistência, notificação) sai como
/// `SessionEffect` para o `SessionCoordinator` interpretar. Isso torna as transições 100%
/// testáveis por tabela (RNF-05) e concentra a regra de sequenciamento de fases num único lugar (SRP).
public enum SessionStateMachine {

    public static func reduce(
        state: SessionMachineState,
        event: SessionEvent,
        config: PomodoroConfiguration,
        now: Date,
        newID: UUID
    ) -> (state: SessionMachineState, effects: [SessionEffect]) {
        switch state {
        case .idle:
            return reduceIdle(event: event, config: config, now: now, newID: newID)
        case .running(let session):
            return reduceRunning(session: session, event: event, config: config, now: now, newID: newID)
        case .paused(let session, let remaining):
            return reducePaused(session: session, remaining: remaining, event: event,
                                config: config, now: now, newID: newID)
        case .awaitingNext(let phase, let cycle, let taskIDs):
            return reduceAwaiting(phase: phase, cycle: cycle, taskIDs: taskIDs, event: event,
                                  config: config, now: now, newID: newID)
        }
    }

    // MARK: - idle

    private static func reduceIdle(
        event: SessionEvent, config: PomodoroConfiguration, now: Date, newID: UUID
    ) -> (SessionMachineState, [SessionEffect]) {
        switch event {
        case .startFocus(let taskIDs):
            let session = makeFocus(
                cycle: 1, taskIDs: taskIDs, config: config, now: now, id: newID)
            return (.running(session), [.activateBlocking, .persistActive(session)])

        case .adoptRecovered(let session):
            // Só reativa bloqueio se a fase o exige — readotar um intervalo não pode bloquear nada.
            var effects: [SessionEffect] = []
            if session.phase.appliesBlocking {
                effects = [.activateBlocking, .persistActive(session)]
            }
            return (.running(session), effects)

        default:
            return (.idle, [])
        }
    }

    // MARK: - running

    private static func reduceRunning(
        session: PomodoroSession, event: SessionEvent,
        config: PomodoroConfiguration, now: Date, newID: UUID
    ) -> (SessionMachineState, [SessionEffect]) {
        switch event {
        case .tick:
            guard session.isExpired(now: now) else { return (.running(session), []) }
            return handlePhaseCompletion(of: session, config: config, now: now, newID: newID)

        case .pause:
            return (.paused(session: session, remaining: session.remaining(now: now)), [])

        case .cancel:
            return (.idle, cancelEffects(for: session, now: now))

        case .skipPhase:
            return endPhase(session, outcome: .skipped, config: config, now: now, newID: newID)

        case .startFocus, .resume, .beginNextPhase, .adoptRecovered, .changeTask:
            return (.running(session), [])
        }
    }

    /// Sessão expirou: fecha a fase corrente e decide a próxima.
    private static func handlePhaseCompletion(
        of session: PomodoroSession, config: PomodoroConfiguration, now: Date, newID: UUID
    ) -> (SessionMachineState, [SessionEffect]) {
        endPhase(session, outcome: .completed, config: config, now: now, newID: newID)
    }

    /// Encerra a fase corrente — por término natural (`.completed`) ou por pulo do usuário
    /// (`.skipped`) — e emite a transição para a próxima. Único lugar que decide sequenciamento,
    /// então pular e terminar naturalmente nunca divergem.
    private static func endPhase(
        _ session: PomodoroSession, outcome: SessionRecord.Outcome,
        config: PomodoroConfiguration, now: Date, newID: UUID
    ) -> (SessionMachineState, [SessionEffect]) {
        // Pulo encerra no instante do clique; término natural, no `endsAt` planejado.
        let record = SessionRecord(
            sessionID: session.id, phase: session.phase,
            startedAt: session.startedAt,
            endedAt: outcome == .completed ? session.endsAt : now,
            outcome: outcome, cycleNumber: session.cycleNumber,
            taskIDs: session.taskIDs
        )

        switch session.phase {
        case .focus:
            // Fim do foco → sempre desativa bloqueio e limpa o failsafe, ANTES de decidir
            // se o intervalo começa sozinho: ninguém pode ficar bloqueado esperando confirmação.
            // `max(1, …)`: a UI limita a 1...12, mas a config vem de UserDefaults decodificado sem
            // validação — um plist editado ou versão antiga com 0 causaria crash de módulo por zero.
            let isLong = session.cycleNumber % max(1, config.cyclesBeforeLongBreak) == 0
            let breakPhase: SessionPhase = isLong ? .longBreak : .shortBreak
            let common: [SessionEffect] = [
                .deactivateBlocking, .clearActive,
                .recordHistory(record), .notify(.focusEnded)
            ]
            guard config.autoAdvancePhases else {
                return (.awaitingNext(phase: breakPhase, cycle: session.cycleNumber,
                                      taskIDs: session.taskIDs), common)
            }
            let breakSession = makeSession(
                phase: breakPhase, cycle: session.cycleNumber,
                taskIDs: session.taskIDs, config: config, now: now, id: newID
            )
            return (.running(breakSession), common)

        case .shortBreak, .longBreak:
            // Fim do intervalo → próximo foco (RF-01.4).
            let event: NotificationEvent = session.phase == .longBreak ? .longBreakEnded : .shortBreakEnded
            let nextCycle = session.cycleNumber + 1
            guard config.autoAdvancePhases else {
                return (.awaitingNext(phase: .focus, cycle: nextCycle, taskIDs: session.taskIDs),
                        [.recordHistory(record), .notify(event)])
            }
            let focus = makeFocus(cycle: nextCycle, taskIDs: session.taskIDs,
                                  config: config, now: now, id: newID)
            return (.running(focus), [
                .recordHistory(record), .notify(event),
                .activateBlocking, .persistActive(focus)
            ])

        case .idle:
            return (.running(session), [])  // estado impossível; sem transição
        }
    }

    // MARK: - paused

    private static func reducePaused(
        session: PomodoroSession, remaining: TimeInterval, event: SessionEvent,
        config: PomodoroConfiguration, now: Date, newID: UUID
    ) -> (SessionMachineState, [SessionEffect]) {
        switch event {
        case .resume:
            let resumed = PomodoroSession(
                id: session.id, phase: session.phase, startedAt: session.startedAt,
                endsAt: now.addingTimeInterval(remaining),
                cycleNumber: session.cycleNumber, taskIDs: session.taskIDs
            )
            let effects: [SessionEffect] = session.phase.appliesBlocking ? [.persistActive(resumed)] : []
            return (.running(resumed), effects)
        case .cancel:
            return (.idle, cancelEffects(for: session, now: now))
        case .skipPhase:
            return endPhase(session, outcome: .skipped, config: config, now: now, newID: newID)
        case .changeTask(let taskIDs):
            // Troca as tarefas sem mexer no tempo restante. Re-persiste o failsafe quando a fase
            // bloqueia, para o snapshot pós-crash refletir as novas tarefas.
            let updated = session.with(taskIDs: taskIDs)
            let effects: [SessionEffect] = updated.phase.appliesBlocking ? [.persistActive(updated)] : []
            return (.paused(session: updated, remaining: remaining), effects)
        case .tick, .pause, .startFocus, .beginNextPhase, .adoptRecovered:
            return (.paused(session: session, remaining: remaining), [])
        }
    }

    // MARK: - awaitingNext

    private static func reduceAwaiting(
        phase: SessionPhase, cycle: Int, taskIDs: [UUID], event: SessionEvent,
        config: PomodoroConfiguration, now: Date, newID: UUID
    ) -> (SessionMachineState, [SessionEffect]) {
        switch event {
        case .beginNextPhase, .startFocus:
            let next = makeSession(
                phase: phase, cycle: cycle, taskIDs: taskIDs,
                config: config, now: now, id: newID)
            // Só o foco bloqueia: confirmar um intervalo não pode ligar bloqueio nenhum.
            let effects: [SessionEffect] = phase.appliesBlocking
                ? [.activateBlocking, .persistActive(next)]
                : []
            return (.running(next), effects)
        case .cancel:
            return (.idle, [])
        case .tick, .pause, .resume, .skipPhase, .adoptRecovered, .changeTask:
            return (.awaitingNext(phase: phase, cycle: cycle, taskIDs: taskIDs), [])
        }
    }

    // MARK: - helpers

    /// Efeitos de cancelar uma sessão. Ports são idempotentes (RNF-01), então emitir
    /// `deactivateBlocking`/`clearActive` fora do foco é seguro; só emitimos deactivate quando faz sentido.
    private static func cancelEffects(for session: PomodoroSession, now: Date) -> [SessionEffect] {
        let record = SessionRecord(
            sessionID: session.id, phase: session.phase,
            startedAt: session.startedAt, endedAt: now,
            outcome: .cancelled, cycleNumber: session.cycleNumber,
            taskIDs: session.taskIDs
        )
        var effects: [SessionEffect] = []
        if session.phase.appliesBlocking { effects.append(.deactivateBlocking) }
        effects.append(.clearActive)
        effects.append(.recordHistory(record))
        return effects
    }

    private static func makeFocus(
        cycle: Int, taskIDs: [UUID],
        config: PomodoroConfiguration, now: Date, id: UUID
    ) -> PomodoroSession {
        makeSession(phase: .focus, cycle: cycle, taskIDs: taskIDs,
                    config: config, now: now, id: id)
    }

    private static func makeSession(
        phase: SessionPhase, cycle: Int, taskIDs: [UUID],
        config: PomodoroConfiguration, now: Date, id: UUID
    ) -> PomodoroSession {
        PomodoroSession(
            id: id, phase: phase, startedAt: now,
            endsAt: now.addingTimeInterval(config.duration(for: phase)),
            cycleNumber: cycle, taskIDs: taskIDs
        )
    }
}
