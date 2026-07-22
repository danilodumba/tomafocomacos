import XCTest
import TomafocoDomain
import TomafocoTestSupport
@testable import TomafocoApplication

@MainActor
final class SessionCoordinatorTests: XCTestCase {

    private func makeSUT(
        config: PomodoroConfiguration = .init(),
        blockList: BlockList = .init(),
        websiteError: Error? = nil
    ) -> (SessionCoordinator, FakeClock, SpyAppBlocker, SpyWebsiteBlocker, InMemorySessionRepository, SpyNotifier) {
        let clock = FakeClock()
        let appBlocker = SpyAppBlocker()
        let webBlocker = SpyWebsiteBlocker()
        webBlocker.activationError = websiteError
        let sessions = InMemorySessionRepository()
        let settings = InMemorySettingsRepository(configuration: config, blockList: blockList)
        let notifier = SpyNotifier()
        let sut = SessionCoordinator(
            clock: clock, appBlocker: appBlocker, websiteBlocker: webBlocker,
            sessions: sessions, settings: settings, notifier: notifier,
            makeID: { UUID() }
        )
        return (sut, clock, appBlocker, webBlocker, sessions, notifier)
    }

    func test_startFocus_ativaBloqueiosEPersisteFailsafe() async throws {
        let apps = [BlockedApp(bundleID: "com.tinyspeck.slackmacgap", displayName: "Slack")]
        let (sut, _, appBlocker, webBlocker, sessions, _) = makeSUT(
            blockList: BlockList(domains: [try BlockedDomain(raw: "twitter.com")], apps: apps))

        try await sut.startFocus(reason: nil)

        XCTAssertEqual(appBlocker.activateCallCount, 1)
        XCTAssertEqual(appBlocker.lastBundleIDs, ["com.tinyspeck.slackmacgap"])
        XCTAssertEqual(webBlocker.activateCallCount, 1)
        XCTAssertNotNil(sessions.active)                      // failsafe persistido
        XCTAssertFalse(sut.websiteBlockingUnavailable)
    }

    func test_startFocus_falhaNoBloqueioDeSites_marcaIndisponivel() async throws {
        struct Boom: Error {}
        let (sut, _, _, _, _, notifier) = makeSUT(websiteError: Boom())
        try await sut.startFocus(reason: nil)
        XCTAssertTrue(sut.websiteBlockingUnavailable)
        XCTAssertTrue(notifier.events.contains(.websiteBlockingUnavailable))
    }

    func test_startFocus_hardcoreExigeMotivo_semMotivo_lanca() async {
        let config = PomodoroConfiguration(hardcore: .init(isEnabled: true, requireReason: true))
        let (sut, _, _, _, _, _) = makeSUT(config: config)
        do {
            try await sut.startFocus(reason: "   ")
            XCTFail("esperava DomainError.reasonRequired")
        } catch {
            XCTAssertEqual(error as? DomainError, .reasonRequired)
        }
    }

    func test_cancel_dentroDaCarenciaHardcore_lancaENaoDesativa() async throws {
        let config = PomodoroConfiguration(
            hardcore: .init(isEnabled: true, minimumMinutesBeforeCancel: 5, requireReason: false))
        let (sut, _, appBlocker, _, _, _) = makeSUT(config: config)
        try await sut.startFocus(reason: "foco")

        do {
            try await sut.cancel()
            XCTFail("esperava bloqueio de cancelamento")
        } catch {
            guard case DomainError.cancellationBlockedByHardcore = error else {
                return XCTFail("erro inesperado: \(error)")
            }
        }
        XCTAssertEqual(appBlocker.deactivateCallCount, 0)     // bloqueio permaneceu
    }

    func test_cancel_semHardcore_desativaBloqueioEVoltaParaIdle() async throws {
        let (sut, _, appBlocker, webBlocker, sessions, _) = makeSUT()
        try await sut.startFocus(reason: nil)
        try await sut.cancel()

        XCTAssertEqual(appBlocker.deactivateCallCount, 1)
        XCTAssertEqual(webBlocker.deactivateCallCount, 1)
        XCTAssertNil(sessions.active)
        XCTAssertEqual(sut.state, .idle)
    }

    // MARK: - Recuperação pós-crash (UC-04, T-21)

    func test_adoptRecoveredSession_reativaBloqueiosEVoltaACronometrar() async throws {
        let apps = [BlockedApp(bundleID: "com.tinyspeck.slackmacgap", displayName: "Slack")]
        let (sut, clock, appBlocker, webBlocker, sessions, _) = makeSUT(
            blockList: BlockList(domains: [try BlockedDomain(raw: "globo.com")], apps: apps))
        let pendente = PomodoroSession(
            id: UUID(), phase: .focus, startedAt: clock.now.addingTimeInterval(-600),
            endsAt: clock.now.addingTimeInterval(900), reason: "código", cycleNumber: 2)

        await sut.adoptRecoveredSession(pendente)

        XCTAssertEqual(sut.state, .running(pendente))
        XCTAssertEqual(appBlocker.activateCallCount, 1)
        XCTAssertEqual(webBlocker.activateCallCount, 1)
        XCTAssertEqual(sessions.active, pendente)          // failsafe regravado
        XCTAssertTrue(clock.hasActiveSubscription)         // voltou a contar
    }

    /// Readotada perto do fim, a sessão precisa completar normalmente no primeiro tick —
    /// e não ficar presa mostrando 00:00.
    func test_adoptRecoveredSession_jaExpirada_completaNoPrimeiroTick() async throws {
        let (sut, clock, appBlocker, _, _, notifier) = makeSUT(
            config: PomodoroConfiguration(autoAdvancePhases: true))
        let quaseNoFim = PomodoroSession(
            id: UUID(), phase: .focus, startedAt: clock.now.addingTimeInterval(-1500),
            endsAt: clock.now.addingTimeInterval(1), reason: nil, cycleNumber: 1)

        await sut.adoptRecoveredSession(quaseNoFim)
        clock.advance(by: 2)
        try await Task.sleep(nanoseconds: 100_000_000)     // o tick despacha numa Task

        guard case .running(let atual) = sut.state else { return XCTFail("esperava running") }
        XCTAssertEqual(atual.phase, .shortBreak)           // foco terminou, entrou no intervalo
        XCTAssertEqual(appBlocker.deactivateCallCount, 1)  // bloqueio liberado
        XCTAssertTrue(notifier.events.contains(.focusEnded))
    }

    // MARK: - skipPhase (RF-04.2)

    func test_skipPhase_noFoco_semHardcore_liberaBloqueioEVaiParaIntervalo() async throws {
        let (sut, _, appBlocker, webBlocker, sessions, _) = makeSUT(
            config: PomodoroConfiguration(autoAdvancePhases: true))
        try await sut.startFocus(reason: nil)

        try await sut.skipPhase()

        guard case .running(let session) = sut.state else { return XCTFail("esperava running") }
        XCTAssertEqual(session.phase, .shortBreak)
        XCTAssertEqual(appBlocker.deactivateCallCount, 1)
        XCTAssertEqual(webBlocker.deactivateCallCount, 1)
        XCTAssertNil(sessions.active)                          // failsafe limpo
    }

    /// SKIP encerra o foco antes da hora, então precisa respeitar a carência do hardcore —
    /// sem isso o botão seria um atalho para burlar o RF-06.1.
    func test_skipPhase_noFoco_dentroDaCarenciaHardcore_eRejeitado() async throws {
        let config = PomodoroConfiguration(
            hardcore: HardcoreOptions(isEnabled: true, minimumMinutesBeforeCancel: 5))
        let (sut, _, appBlocker, _, _, _) = makeSUT(config: config)
        try await sut.startFocus(reason: "foco")

        do {
            try await sut.skipPhase()
            XCTFail("esperava bloqueio do pulo")
        } catch {
            guard case DomainError.cancellationBlockedByHardcore = error else {
                return XCTFail("erro inesperado: \(error)")
            }
        }
        XCTAssertEqual(appBlocker.deactivateCallCount, 0)      // bloqueio permaneceu
        guard case .running(let session) = sut.state else { return XCTFail("esperava running") }
        XCTAssertEqual(session.phase, .focus)                  // continua no foco
    }

    /// A trava é do foco; um intervalo pode ser pulado mesmo com hardcore ligado.
    func test_skipPhase_noIntervalo_comHardcore_ePermitido() async throws {
        let config = PomodoroConfiguration(
            autoAdvancePhases: true,
            hardcore: HardcoreOptions(isEnabled: true, minimumMinutesBeforeCancel: 5))
        let (sut, clock, _, _, _, _) = makeSUT(config: config)
        try await sut.startFocus(reason: "foco")
        // Passa da carência e pula o foco para chegar ao intervalo sem depender do tick assíncrono.
        clock.advance(by: 6 * 60)
        try await sut.skipPhase()
        guard case .running(let br) = sut.state, br.phase == .shortBreak else {
            return XCTFail("esperava intervalo em andamento")
        }

        try await sut.skipPhase()

        // Com avanço automático ligado, pular o intervalo emenda direto no próximo foco.
        guard case .running(let proximo) = sut.state else { return XCTFail("esperava running") }
        XCTAssertEqual(proximo.phase, .focus)
        XCTAssertEqual(proximo.cycleNumber, 2)
    }

    /// O bug relatado em 2026-07-22: com o avanço automático DESLIGADO, terminar o foco
    /// não podia emendar o intervalo sozinho — o app tem que esperar confirmação.
    func test_fimDoFoco_semAutoAvanco_naoEmendaIntervaloSozinho() async throws {
        let (sut, clock, appBlocker, _, sessions, notifier) = makeSUT(
            config: PomodoroConfiguration(focusDuration: 60, autoAdvancePhases: false))
        try await sut.startFocus(reason: nil)

        clock.advance(by: 61)
        try await Task.sleep(nanoseconds: 100_000_000)   // o tick despacha numa Task

        XCTAssertEqual(sut.state, .awaitingNext(phase: .shortBreak, cycle: 1))
        XCTAssertTrue(notifier.events.contains(.focusEnded))
        XCTAssertEqual(appBlocker.deactivateCallCount, 1)  // bloqueio cai mesmo aguardando
        XCTAssertNil(sessions.active)
    }
}
