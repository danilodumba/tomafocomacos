import XCTest
import TomafocoDomain
@testable import TomafocoApplication

/// A tela cheia cobre o monitor do usuário — mostrar na hora errada é intrusivo, então
/// a bateria cobre principalmente quando ela NÃO deve aparecer.
final class BreakOverlayPolicyTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_000_000)

    private func session(_ phase: SessionPhase, cycle: Int = 1, id: UUID = UUID()) -> PomodoroSession {
        PomodoroSession(id: id, phase: phase, startedAt: now,
                        endsAt: now.addingTimeInterval(300), reason: nil, cycleNumber: cycle)
    }

    // MARK: - Mostra

    func test_intervaloCurtoEmAndamento_mostra() {
        XCTAssertNotNil(BreakOverlayPolicy.presentationKey(for: .running(session(.shortBreak))))
    }

    func test_intervaloLongoEmAndamento_mostra() {
        XCTAssertNotNil(BreakOverlayPolicy.presentationKey(for: .running(session(.longBreak))))
    }

    /// Foco acabou e o intervalo espera confirmação: é o momento de chamar a atenção.
    func test_aguardandoIntervalo_mostra() {
        XCTAssertNotNil(
            BreakOverlayPolicy.presentationKey(for: .awaitingNext(phase: .shortBreak, cycle: 2)))
    }

    func test_intervaloPausado_continuaMostrando() {
        let state = SessionMachineState.paused(session: session(.shortBreak), remaining: 120)
        XCTAssertNotNil(BreakOverlayPolicy.presentationKey(for: state))
    }

    // MARK: - NÃO mostra

    /// Cobrir a tela durante o foco seria o oposto do produto.
    func test_focoEmAndamento_naoMostra() {
        XCTAssertNil(BreakOverlayPolicy.presentationKey(for: .running(session(.focus))))
    }

    func test_focoPausado_naoMostra() {
        let state = SessionMachineState.paused(session: session(.focus), remaining: 600)
        XCTAssertNil(BreakOverlayPolicy.presentationKey(for: state))
    }

    /// Aguardando o próximo FOCO o intervalo já acabou — a tela tem que sair.
    func test_aguardandoProximoFoco_naoMostra() {
        XCTAssertNil(BreakOverlayPolicy.presentationKey(for: .awaitingNext(phase: .focus, cycle: 3)))
    }

    func test_ocioso_naoMostra() {
        XCTAssertNil(BreakOverlayPolicy.presentationKey(for: .idle))
    }

    // MARK: - Identidade da chave

    /// Dispensar a tela de um intervalo não pode dispensar a do próximo.
    func test_intervalosDiferentes_temChavesDiferentes() {
        let primeiro = BreakOverlayPolicy.presentationKey(for: .running(session(.shortBreak)))
        let segundo = BreakOverlayPolicy.presentationKey(for: .running(session(.shortBreak)))
        XCTAssertNotEqual(primeiro, segundo)
    }

    func test_mesmoIntervalo_mantemAChaveEntreTicks() {
        let id = UUID()
        let a = BreakOverlayPolicy.presentationKey(for: .running(session(.shortBreak, id: id)))
        let b = BreakOverlayPolicy.presentationKey(for: .running(session(.shortBreak, id: id)))
        XCTAssertEqual(a, b)
    }

    /// A espera e o intervalo já iniciado são momentos distintos: se compartilhassem a chave,
    /// dispensar o aviso faria a tela do intervalo em si nunca aparecer.
    func test_esperaEIntervaloIniciado_naoCompartilhamChave() {
        let esperando = BreakOverlayPolicy.presentationKey(for: .awaitingNext(phase: .shortBreak, cycle: 1))
        let rodando = BreakOverlayPolicy.presentationKey(for: .running(session(.shortBreak, cycle: 1)))
        XCTAssertNotEqual(esperando, rodando)
    }

    func test_ciclosDiferentesNaEspera_temChavesDiferentes() {
        let c1 = BreakOverlayPolicy.presentationKey(for: .awaitingNext(phase: .shortBreak, cycle: 1))
        let c2 = BreakOverlayPolicy.presentationKey(for: .awaitingNext(phase: .shortBreak, cycle: 2))
        XCTAssertNotEqual(c1, c2)
    }
}
