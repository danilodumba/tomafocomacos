import XCTest
@testable import TomafocoDomain

final class AppLaunchGateTests: XCTestCase {

    private let slack = "com.tinyspeck.slackmacgap"

    func test_semSenha_encerra() {
        var gate = AppLaunchGate()
        XCTAssertEqual(gate.decideLaunch(bundleID: slack, pid: 10, hasPassword: false), .terminate)
    }

    func test_comSenha_encerraEPede() {
        var gate = AppLaunchGate()
        XCTAssertEqual(gate.decideLaunch(bundleID: slack, pid: 10, hasPassword: true), .terminateAndPrompt)
    }

    func test_promptAberto_novasAberturasSaoSilenciosas() {
        var gate = AppLaunchGate()
        _ = gate.decideLaunch(bundleID: slack, pid: 10, hasPassword: true)
        XCTAssertEqual(gate.decideLaunch(bundleID: slack, pid: 11, hasPassword: true), .terminateSilently)
    }

    func test_promptDeUmApp_naoCalaOutro() {
        var gate = AppLaunchGate()
        _ = gate.decideLaunch(bundleID: slack, pid: 10, hasPassword: true)
        XCTAssertEqual(gate.decideLaunch(bundleID: "com.spotify.client", pid: 20, hasPassword: true),
                       .terminateAndPrompt)
    }

    func test_desbloqueado_relancamentoPassaEFicaLiberadoAteFechar() {
        var gate = AppLaunchGate()
        _ = gate.decideLaunch(bundleID: slack, pid: 10, hasPassword: true)
        gate.unlock(bundleID: slack, runningPID: nil)

        XCTAssertEqual(gate.decideLaunch(bundleID: slack, pid: 11, hasPassword: true), .allow)
        XCTAssertTrue(gate.isUnlocked(pid: 11))

        gate.didTerminate(pid: 11)
        XCTAssertFalse(gate.isUnlocked(pid: 11))
        XCTAssertEqual(gate.decideLaunch(bundleID: slack, pid: 12, hasPassword: true), .terminateAndPrompt)
    }

    func test_terminoAtrasadoDaInstanciaVelha_naoRevogaANova() {
        var gate = AppLaunchGate()
        _ = gate.decideLaunch(bundleID: slack, pid: 10, hasPassword: true)
        gate.unlock(bundleID: slack, runningPID: nil)
        _ = gate.decideLaunch(bundleID: slack, pid: 11, hasPassword: true)

        gate.didTerminate(pid: 10)
        XCTAssertTrue(gate.isUnlocked(pid: 11))
    }

    func test_instanciaQueNaoFechou_eLiberadaDireto() {
        var gate = AppLaunchGate()
        _ = gate.decideLaunch(bundleID: slack, pid: 10, hasPassword: true)
        gate.unlock(bundleID: slack, runningPID: 10)
        XCTAssertTrue(gate.isUnlocked(pid: 10))
        // Sem liberação pendente: outra instância pergunta de novo.
        XCTAssertEqual(gate.decideLaunch(bundleID: slack, pid: 11, hasPassword: true), .terminateAndPrompt)
    }

    func test_isPrompting_duranteOPromptAteDesbloquearOuCancelar() {
        var gate = AppLaunchGate()
        _ = gate.decideLaunch(bundleID: slack, pid: 10, hasPassword: true)
        XCTAssertTrue(gate.isPrompting(bundleID: slack))
        gate.unlock(bundleID: slack, runningPID: 10)
        XCTAssertFalse(gate.isPrompting(bundleID: slack))

        _ = gate.decideLaunch(bundleID: slack, pid: 11, hasPassword: true)
        gate.cancelPrompt(bundleID: slack)
        XCTAssertFalse(gate.isPrompting(bundleID: slack))
    }

    func test_cancelar_proximaAberturaPerguntaDeNovo() {
        var gate = AppLaunchGate()
        _ = gate.decideLaunch(bundleID: slack, pid: 10, hasPassword: true)
        gate.cancelPrompt(bundleID: slack)
        XCTAssertEqual(gate.decideLaunch(bundleID: slack, pid: 11, hasPassword: true), .terminateAndPrompt)
    }

    func test_relancamentoFalhou_proximaAberturaNaoPassaSemSenha() {
        var gate = AppLaunchGate()
        _ = gate.decideLaunch(bundleID: slack, pid: 10, hasPassword: true)
        gate.unlock(bundleID: slack, runningPID: nil)
        gate.abandonPendingLaunch(bundleID: slack)
        XCTAssertEqual(gate.decideLaunch(bundleID: slack, pid: 11, hasPassword: true), .terminateAndPrompt)
    }

    func test_regraDeSenha_rejeitaCurta() {
        XCTAssertThrowsError(try AppUnlockPasswordRule.validate("123")) { error in
            XCTAssertEqual(error as? DomainError, .weakPassword(minimumLength: 4))
        }
        XCTAssertNoThrow(try AppUnlockPasswordRule.validate("1234"))
    }
}
