import XCTest
@testable import TomafocoApplication

final class BlockedAppAlertThrottleTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_000_000)

    func test_primeiraTentativa_mostra() {
        var sut = BlockedAppAlertThrottle(cooldown: 5)
        XCTAssertTrue(sut.shouldPresent(app: "Slack", now: now))
    }

    /// Clicar três vezes no ícone não pode gerar três avisos idênticos.
    func test_tentativasSeguidasDentroDaCarencia_naoRepetem() {
        var sut = BlockedAppAlertThrottle(cooldown: 5)
        _ = sut.shouldPresent(app: "Slack", now: now)

        XCTAssertFalse(sut.shouldPresent(app: "Slack", now: now.addingTimeInterval(1)))
        XCTAssertFalse(sut.shouldPresent(app: "Slack", now: now.addingTimeInterval(4.9)))
    }

    func test_aposACarencia_mostraDeNovo() {
        var sut = BlockedAppAlertThrottle(cooldown: 5)
        _ = sut.shouldPresent(app: "Slack", now: now)

        XCTAssertTrue(sut.shouldPresent(app: "Slack", now: now.addingTimeInterval(5)))
    }

    /// Um app que relança em loop não pode calar o aviso de outro app.
    func test_appsDiferentes_temRepresasIndependentes() {
        var sut = BlockedAppAlertThrottle(cooldown: 5)
        _ = sut.shouldPresent(app: "Slack", now: now)

        XCTAssertTrue(sut.shouldPresent(app: "Discord", now: now.addingTimeInterval(1)))
    }

    /// A carência conta a partir da última EXIBIÇÃO; tentativas represadas não a renovam,
    /// senão um app em loop rápido nunca mais avisaria.
    func test_tentativasRepresadas_naoRenovamACarencia() {
        var sut = BlockedAppAlertThrottle(cooldown: 5)
        _ = sut.shouldPresent(app: "Slack", now: now)
        _ = sut.shouldPresent(app: "Slack", now: now.addingTimeInterval(3))
        _ = sut.shouldPresent(app: "Slack", now: now.addingTimeInterval(4))

        XCTAssertTrue(sut.shouldPresent(app: "Slack", now: now.addingTimeInterval(5)))
    }

    func test_reset_liberaAvisoImediato() {
        var sut = BlockedAppAlertThrottle(cooldown: 5)
        _ = sut.shouldPresent(app: "Slack", now: now)

        sut.reset()

        XCTAssertTrue(sut.shouldPresent(app: "Slack", now: now.addingTimeInterval(1)))
    }
}
