import XCTest
@testable import TomafocoInfrastructure

/// Cobre o mapeamento de estado do helper e — o que mais importa — a sincronia do `readiness`,
/// que é o que o bloqueio de sites consulta de outra thread.
final class PrivilegedHelperInstallerTests: XCTestCase {

    private final class FakeService: HelperServiceControlling, @unchecked Sendable {
        var currentStatus: HelperStatus
        var registerError: Error?
        var unregisterError: Error?
        private(set) var registerCallCount = 0
        private(set) var unregisterCallCount = 0
        private(set) var openSettingsCallCount = 0

        init(status: HelperStatus = .notInstalled) {
            self.currentStatus = status
        }

        var status: HelperStatus { currentStatus }

        func register() throws {
            registerCallCount += 1
            if let registerError { throw registerError }
            currentStatus = .awaitingApproval      // comportamento real do SMAppService
        }

        func unregister() throws {
            unregisterCallCount += 1
            if let unregisterError { throw unregisterError }
            currentStatus = .notInstalled
        }

        func openSystemSettings() { openSettingsCallCount += 1 }
    }

    private struct Boom: LocalizedError {
        var errorDescription: String? { "sem Developer ID" }
    }

    func test_init_jaRefletirOEstadoDoServico() {
        let sut = PrivilegedHelperInstaller(service: FakeService(status: .installed))

        XCTAssertEqual(sut.status, .installed)
        XCTAssertTrue(sut.readiness.isReady)      // snapshot sincronizado já no arranque
    }

    func test_readiness_falsoQuandoNaoInstalado() {
        let sut = PrivilegedHelperInstaller(service: FakeService(status: .notInstalled))
        XCTAssertFalse(sut.readiness.isReady)
    }

    /// Aguardando aprovação NÃO é pronto: usar XPC aqui falharia e degradaria à toa.
    func test_readiness_falsoEnquantoAguardaAprovacao() {
        let sut = PrivilegedHelperInstaller(service: FakeService(status: .awaitingApproval))

        XCTAssertEqual(sut.status, .awaitingApproval)
        XCTAssertFalse(sut.readiness.isReady)
    }

    func test_install_registraEAtualizaEstado() {
        let service = FakeService(status: .notInstalled)
        let sut = PrivilegedHelperInstaller(service: service)

        sut.install()

        XCTAssertEqual(service.registerCallCount, 1)
        XCTAssertEqual(sut.status, .awaitingApproval)
        XCTAssertNil(sut.lastError)
        XCTAssertFalse(sut.readiness.isReady)
    }

    func test_install_comFalha_guardaMensagemEMantemEstado() {
        let service = FakeService(status: .notInstalled)
        service.registerError = Boom()
        let sut = PrivilegedHelperInstaller(service: service)

        sut.install()

        XCTAssertEqual(sut.status, .notInstalled)
        XCTAssertEqual(sut.lastError, "não foi possível registrar o helper: sem Developer ID")
        XCTAssertFalse(sut.readiness.isReady)
    }

    func test_uninstall_removeEDesligaReadiness() {
        let service = FakeService(status: .installed)
        let sut = PrivilegedHelperInstaller(service: service)
        XCTAssertTrue(sut.readiness.isReady)

        sut.uninstall()

        XCTAssertEqual(service.unregisterCallCount, 1)
        XCTAssertEqual(sut.status, .notInstalled)
        XCTAssertFalse(sut.readiness.isReady)
    }

    func test_uninstall_comFalha_guardaMensagem() {
        let service = FakeService(status: .installed)
        service.unregisterError = Boom()
        let sut = PrivilegedHelperInstaller(service: service)

        sut.uninstall()

        XCTAssertEqual(sut.lastError, "não foi possível remover o helper: sem Developer ID")
        XCTAssertTrue(sut.readiness.isReady)      // continua instalado
    }

    /// A aprovação acontece fora do app; `refresh` é como o estado entra.
    func test_refresh_capturaAprovacaoFeitaForaDoApp() {
        let service = FakeService(status: .awaitingApproval)
        let sut = PrivilegedHelperInstaller(service: service)
        XCTAssertFalse(sut.readiness.isReady)

        service.currentStatus = .installed
        let status = sut.refresh()

        XCTAssertEqual(status, .installed)
        XCTAssertTrue(sut.readiness.isReady)
    }

    func test_install_limpaErroAnterior() {
        let service = FakeService(status: .notInstalled)
        service.registerError = Boom()
        let sut = PrivilegedHelperInstaller(service: service)
        sut.install()
        XCTAssertNotNil(sut.lastError)

        service.registerError = nil
        sut.install()

        XCTAssertNil(sut.lastError)
    }

    func test_openSystemSettings_encaminhaParaOServico() {
        let service = FakeService()
        let sut = PrivilegedHelperInstaller(service: service)

        sut.openSystemSettings()

        XCTAssertEqual(service.openSettingsCallCount, 1)
    }

    func test_unsupported_naoEhPronto() {
        let sut = PrivilegedHelperInstaller(service: FakeService(status: .unsupported("sem bundle")))

        XCTAssertFalse(sut.readiness.isReady)
        XCTAssertEqual(sut.status, .unsupported("sem bundle"))
    }
}

/// O snapshot é lido do pool cooperativo enquanto a UI escreve na main — precisa aguentar isso.
final class HelperReadinessTests: XCTestCase {

    func test_valorInicial() {
        XCTAssertFalse(HelperReadiness().isReady)
        XCTAssertTrue(HelperReadiness(isReady: true).isReady)
    }

    func test_set_alteraOValorLido() {
        let sut = HelperReadiness()
        sut.set(true)
        XCTAssertTrue(sut.isReady)
        sut.set(false)
        XCTAssertFalse(sut.isReady)
    }

    /// Sem o lock, este teste dispara o Thread Sanitizer / corrompe o valor.
    func test_leituraEEscritaConcorrentes_naoQuebram() {
        let sut = HelperReadiness()
        let iterations = 1_000
        let done = expectation(description: "concorrência")
        done.expectedFulfillmentCount = 2

        DispatchQueue.global().async {
            for index in 0..<iterations { sut.set(index % 2 == 0) }
            done.fulfill()
        }
        DispatchQueue.global().async {
            for _ in 0..<iterations { _ = sut.isReady }
            done.fulfill()
        }

        wait(for: [done], timeout: 5)
    }
}
