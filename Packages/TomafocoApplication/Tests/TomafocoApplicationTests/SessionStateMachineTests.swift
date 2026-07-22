import XCTest
import TomafocoDomain
@testable import TomafocoApplication

/// Testes por tabela das transições da máquina pura (T-06).
final class SessionStateMachineTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_000_000)
    private let id = UUID(uuidString: "00000000-0000-0000-0000-0000000000AA")!

    private func config(
        focus: TimeInterval = 1500, short: TimeInterval = 300, long: TimeInterval = 900,
        cycles: Int = 4, autoStart: Bool = false
    ) -> PomodoroConfiguration {
        PomodoroConfiguration(
            focusDuration: focus, shortBreakDuration: short, longBreakDuration: long,
            cyclesBeforeLongBreak: cycles, autoStartNextFocus: autoStart
        )
    }

    private func focusSession(cycle: Int, startedAt: Date, duration: TimeInterval = 1500, phase: SessionPhase = .focus) -> PomodoroSession {
        PomodoroSession(id: id, phase: phase, startedAt: startedAt,
                        endsAt: startedAt.addingTimeInterval(duration), reason: nil, cycleNumber: cycle)
    }

    // MARK: idle

    func test_idle_startFocus_iniciaRunningComBloqueioEPersistencia() {
        let (state, effects) = SessionStateMachine.reduce(
            state: .idle, event: .startFocus(reason: "código"),
            config: config(), now: now, newID: id
        )
        guard case .running(let s) = state else { return XCTFail("esperava running") }
        XCTAssertEqual(s.phase, .focus)
        XCTAssertEqual(s.cycleNumber, 1)
        XCTAssertEqual(s.endsAt, now.addingTimeInterval(1500))
        XCTAssertTrue(effects.contains(.activateBlocking))
        XCTAssertTrue(effects.contains(.persistActive(s)))
    }

    func test_idle_ignoraOutrosEventos() {
        let (state, effects) = SessionStateMachine.reduce(
            state: .idle, event: .tick, config: config(), now: now, newID: id)
        XCTAssertEqual(state, .idle)
        XCTAssertTrue(effects.isEmpty)
    }

    // MARK: tick durante foco

    func test_running_tickAntesDoFim_semTransicao() {
        let s = focusSession(cycle: 1, startedAt: now)
        let (state, effects) = SessionStateMachine.reduce(
            state: .running(s), event: .tick, config: config(),
            now: now.addingTimeInterval(10), newID: id)
        XCTAssertEqual(state, .running(s))
        XCTAssertTrue(effects.isEmpty)
    }

    func test_running_focoExpira_ciclo1_vaiParaShortBreak() {
        let s = focusSession(cycle: 1, startedAt: now)
        let end = now.addingTimeInterval(1500)
        let (state, effects) = SessionStateMachine.reduce(
            state: .running(s), event: .tick, config: config(), now: end, newID: id)
        guard case .running(let br) = state else { return XCTFail() }
        XCTAssertEqual(br.phase, .shortBreak)
        XCTAssertEqual(br.cycleNumber, 1)
        XCTAssertTrue(effects.contains(.deactivateBlocking))
        XCTAssertTrue(effects.contains(.clearActive))
        XCTAssertTrue(effects.contains(.notify(.focusEnded)))
        XCTAssertTrue(effects.contains { if case .recordHistory = $0 { return true }; return false })
    }

    func test_running_focoExpira_ciclo4_vaiParaLongBreak() {
        let s = focusSession(cycle: 4, startedAt: now)
        let end = now.addingTimeInterval(1500)
        let (state, _) = SessionStateMachine.reduce(
            state: .running(s), event: .tick, config: config(cycles: 4), now: end, newID: id)
        guard case .running(let br) = state else { return XCTFail() }
        XCTAssertEqual(br.phase, .longBreak)
    }

    // MARK: fim de intervalo

    func test_running_shortBreakExpira_semAutoStart_aguardaProximoFoco() {
        let br = focusSession(cycle: 1, startedAt: now, duration: 300, phase: .shortBreak)
        let end = now.addingTimeInterval(300)
        let (state, effects) = SessionStateMachine.reduce(
            state: .running(br), event: .tick, config: config(autoStart: false), now: end, newID: id)
        XCTAssertEqual(state, .awaitingNextFocus(nextCycle: 2))
        XCTAssertTrue(effects.contains(.notify(.shortBreakEnded)))
        XCTAssertFalse(effects.contains(.activateBlocking))
    }

    func test_running_shortBreakExpira_comAutoStart_iniciaProximoFoco() {
        let br = focusSession(cycle: 1, startedAt: now, duration: 300, phase: .shortBreak)
        let end = now.addingTimeInterval(300)
        let (state, effects) = SessionStateMachine.reduce(
            state: .running(br), event: .tick, config: config(autoStart: true), now: end, newID: id)
        guard case .running(let focus) = state else { return XCTFail() }
        XCTAssertEqual(focus.phase, .focus)
        XCTAssertEqual(focus.cycleNumber, 2)
        XCTAssertTrue(effects.contains(.activateBlocking))
        XCTAssertTrue(effects.contains(.persistActive(focus)))
    }

    func test_running_longBreakExpira_notificaLongBreakEnded() {
        let br = focusSession(cycle: 4, startedAt: now, duration: 900, phase: .longBreak)
        let end = now.addingTimeInterval(900)
        let (_, effects) = SessionStateMachine.reduce(
            state: .running(br), event: .tick, config: config(), now: end, newID: id)
        XCTAssertTrue(effects.contains(.notify(.longBreakEnded)))
    }

    // MARK: pausa / retomada

    func test_running_pause_guardaRemaining() {
        let s = focusSession(cycle: 1, startedAt: now)
        let (state, effects) = SessionStateMachine.reduce(
            state: .running(s), event: .pause, config: config(),
            now: now.addingTimeInterval(500), newID: id)
        XCTAssertEqual(state, .paused(session: s, remaining: 1000))
        XCTAssertTrue(effects.isEmpty)
    }

    func test_paused_resume_recalculaTerminoEPersiste() {
        let s = focusSession(cycle: 1, startedAt: now)
        let resumeAt = now.addingTimeInterval(2000)
        let (state, effects) = SessionStateMachine.reduce(
            state: .paused(session: s, remaining: 1000), event: .resume,
            config: config(), now: resumeAt, newID: id)
        guard case .running(let r) = state else { return XCTFail() }
        XCTAssertEqual(r.endsAt, resumeAt.addingTimeInterval(1000))
        XCTAssertTrue(effects.contains(.persistActive(r)))
    }

    // MARK: cancelamento

    func test_running_focoCancel_desativaBloqueioEVaiParaIdle() {
        let s = focusSession(cycle: 1, startedAt: now)
        let (state, effects) = SessionStateMachine.reduce(
            state: .running(s), event: .cancel, config: config(),
            now: now.addingTimeInterval(100), newID: id)
        XCTAssertEqual(state, .idle)
        XCTAssertTrue(effects.contains(.deactivateBlocking))
        XCTAssertTrue(effects.contains(.clearActive))
        XCTAssertTrue(effects.contains { if case .recordHistory(let r) = $0 { return r.outcome == .cancelled }; return false })
    }

    func test_awaiting_beginNextFocus_iniciaFocoComBloqueio() {
        let (state, effects) = SessionStateMachine.reduce(
            state: .awaitingNextFocus(nextCycle: 3), event: .beginNextFocus,
            config: config(), now: now, newID: id)
        guard case .running(let focus) = state else { return XCTFail() }
        XCTAssertEqual(focus.cycleNumber, 3)
        XCTAssertTrue(effects.contains(.activateBlocking))
    }

    // MARK: adoptRecovered (UC-04, T-21)

    func test_adoptRecovered_deIdle_voltaAoFocoEReativaBloqueio() {
        let recuperada = focusSession(cycle: 3, startedAt: now)
        let (state, effects) = SessionStateMachine.reduce(
            state: .idle, event: .adoptRecovered(recuperada),
            config: config(), now: now.addingTimeInterval(120), newID: id)

        XCTAssertEqual(state, .running(recuperada))
        XCTAssertTrue(effects.contains(.activateBlocking))
        XCTAssertTrue(effects.contains(.persistActive(recuperada)))
    }

    /// O término é absoluto: readotar NÃO estende a sessão pelo tempo que o app ficou fora.
    func test_adoptRecovered_preservaOTerminoOriginal() {
        let recuperada = focusSession(cycle: 1, startedAt: now)
        let (state, _) = SessionStateMachine.reduce(
            state: .idle, event: .adoptRecovered(recuperada),
            config: config(), now: now.addingTimeInterval(600), newID: id)

        guard case .running(let adotada) = state else { return XCTFail("esperava running") }
        XCTAssertEqual(adotada.endsAt, recuperada.endsAt)
        XCTAssertEqual(adotada.id, recuperada.id)
    }

    /// Readotar um intervalo não pode ligar bloqueio — ninguém fica bloqueado durante o café.
    func test_adoptRecovered_deIntervalo_naoAtivaBloqueio() {
        let intervalo = focusSession(cycle: 2, startedAt: now, duration: 300, phase: .shortBreak)
        let (state, effects) = SessionStateMachine.reduce(
            state: .idle, event: .adoptRecovered(intervalo), config: config(), now: now, newID: id)

        XCTAssertEqual(state, .running(intervalo))
        XCTAssertTrue(effects.isEmpty)
    }

    /// Só faz sentido a partir de ocioso: com sessão em andamento, readotar sobrescreveria o estado.
    func test_adoptRecovered_comSessaoEmAndamento_ehIgnorado() {
        let atual = focusSession(cycle: 1, startedAt: now)
        let outra = focusSession(cycle: 9, startedAt: now.addingTimeInterval(-5000))
        let (state, effects) = SessionStateMachine.reduce(
            state: .running(atual), event: .adoptRecovered(outra),
            config: config(), now: now, newID: id)

        XCTAssertEqual(state, .running(atual))
        XCTAssertTrue(effects.isEmpty)
    }

    // MARK: skipPhase (RF-04.2)

    func test_skipPhase_duranteIntervalo_semAutoStart_vaiParaAwaiting() {
        let br = focusSession(cycle: 2, startedAt: now, duration: 300, phase: .shortBreak)
        let (state, effects) = SessionStateMachine.reduce(
            state: .running(br), event: .skipPhase, config: config(autoStart: false),
            now: now.addingTimeInterval(60), newID: id)

        XCTAssertEqual(state, .awaitingNextFocus(nextCycle: 3))
        XCTAssertTrue(effects.contains(.notify(.shortBreakEnded)))
        XCTAssertFalse(effects.contains(.activateBlocking))
    }

    func test_skipPhase_duranteIntervalo_comAutoStart_iniciaProximoFoco() {
        let br = focusSession(cycle: 2, startedAt: now, duration: 300, phase: .shortBreak)
        let (state, effects) = SessionStateMachine.reduce(
            state: .running(br), event: .skipPhase, config: config(autoStart: true),
            now: now.addingTimeInterval(60), newID: id)

        guard case .running(let focus) = state else { return XCTFail("esperava running") }
        XCTAssertEqual(focus.phase, .focus)
        XCTAssertEqual(focus.cycleNumber, 3)
        XCTAssertTrue(effects.contains(.activateBlocking))
        XCTAssertTrue(effects.contains(.persistActive(focus)))
    }

    /// O registro do intervalo pulado usa `now` como fim — não o `endsAt` que não chegou a ocorrer.
    func test_skipPhase_gravaHistoricoComoSkippedNoInstanteDoPulo() {
        let br = focusSession(cycle: 2, startedAt: now, duration: 300, phase: .longBreak)
        let skipAt = now.addingTimeInterval(45)
        let (_, effects) = SessionStateMachine.reduce(
            state: .running(br), event: .skipPhase, config: config(), now: skipAt, newID: id)

        let record: SessionRecord? = effects.compactMap {
            if case .recordHistory(let r) = $0 { return r } else { return nil }
        }.first
        XCTAssertEqual(record?.outcome, .skipped)
        XCTAssertEqual(record?.endedAt, skipAt)
        XCTAssertEqual(record?.phase, .longBreak)
    }

    /// Pular o foco encerra o bloqueio e cai no intervalo — mesma transição do término natural.
    func test_skipPhase_duranteFoco_vaiParaIntervaloEDesativaBloqueio() {
        let s = focusSession(cycle: 1, startedAt: now)
        let skipAt = now.addingTimeInterval(30)
        let (state, effects) = SessionStateMachine.reduce(
            state: .running(s), event: .skipPhase, config: config(), now: skipAt, newID: id)

        guard case .running(let br) = state else { return XCTFail("esperava running") }
        XCTAssertEqual(br.phase, .shortBreak)
        XCTAssertEqual(br.cycleNumber, 1)
        XCTAssertTrue(effects.contains(.deactivateBlocking))
        XCTAssertTrue(effects.contains(.clearActive))
        XCTAssertTrue(effects.contains(.notify(.focusEnded)))
        XCTAssertTrue(effects.contains { if case .recordHistory(let r) = $0 { return r.outcome == .skipped && r.endedAt == skipAt }; return false })
    }

    func test_skipPhase_duranteFoco_noCicloDoLongBreak_vaiParaIntervaloLongo() {
        let s = focusSession(cycle: 4, startedAt: now)
        let (state, _) = SessionStateMachine.reduce(
            state: .running(s), event: .skipPhase, config: config(cycles: 4),
            now: now.addingTimeInterval(10), newID: id)

        guard case .running(let br) = state else { return XCTFail("esperava running") }
        XCTAssertEqual(br.phase, .longBreak)
    }

    func test_skipPhase_intervaloPausado_tambemPula() {
        let br = focusSession(cycle: 1, startedAt: now, duration: 300, phase: .shortBreak)
        let (state, _) = SessionStateMachine.reduce(
            state: .paused(session: br, remaining: 120), event: .skipPhase,
            config: config(autoStart: false), now: now.addingTimeInterval(180), newID: id)

        XCTAssertEqual(state, .awaitingNextFocus(nextCycle: 2))
    }

    func test_skipPhase_focoPausado_tambemPulaParaIntervalo() {
        let s = focusSession(cycle: 1, startedAt: now)
        let (state, effects) = SessionStateMachine.reduce(
            state: .paused(session: s, remaining: 600), event: .skipPhase,
            config: config(), now: now.addingTimeInterval(900), newID: id)

        guard case .running(let br) = state else { return XCTFail("esperava running") }
        XCTAssertEqual(br.phase, .shortBreak)
        XCTAssertTrue(effects.contains(.deactivateBlocking))
    }

    func test_skipPhase_idleEAwaiting_saoNoOp() {
        let (idleState, idleEffects) = SessionStateMachine.reduce(
            state: .idle, event: .skipPhase, config: config(), now: now, newID: id)
        XCTAssertEqual(idleState, .idle)
        XCTAssertTrue(idleEffects.isEmpty)

        let (awaitingState, awaitingEffects) = SessionStateMachine.reduce(
            state: .awaitingNextFocus(nextCycle: 2), event: .skipPhase,
            config: config(), now: now, newID: id)
        XCTAssertEqual(awaitingState, .awaitingNextFocus(nextCycle: 2))
        XCTAssertTrue(awaitingEffects.isEmpty)
    }
}
