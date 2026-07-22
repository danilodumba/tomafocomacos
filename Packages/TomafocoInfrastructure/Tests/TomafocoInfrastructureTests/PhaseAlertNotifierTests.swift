import XCTest
import TomafocoDomain
@testable import TomafocoInfrastructure

/// O alerta sonoro é o que avisa o usuário que a etapa acabou quando ele está em outro app.
final class PhaseAlertNotifierTests: XCTestCase {

    private final class SpySound: SoundPlaying, @unchecked Sendable {
        private(set) var playCount = 0
        func playAlert() { playCount += 1 }
    }

    private final class SpyAttention: AttentionRequesting, @unchecked Sendable {
        private(set) var requestCount = 0
        func requestAttention() { requestCount += 1 }
    }

    private final class SpyNotifier: UserNotifying, @unchecked Sendable {
        private(set) var events: [NotificationEvent] = []
        func notify(_ event: NotificationEvent) { events.append(event) }
    }

    private func makeSUT() -> (PhaseAlertNotifier, SpySound, SpyAttention, SpyNotifier) {
        let sound = SpySound()
        let attention = SpyAttention()
        let wrapped = SpyNotifier()
        return (PhaseAlertNotifier(wrapping: wrapped, sound: sound, attention: attention),
                sound, attention, wrapped)
    }

    func test_fimDeFoco_tocaSomEPedeAtencao() {
        let (sut, sound, attention, _) = makeSUT()

        sut.notify(.focusEnded)

        XCTAssertEqual(sound.playCount, 1)
        XCTAssertEqual(attention.requestCount, 1)
    }

    func test_fimDeIntervalo_curtoELongo_tambemAlertam() {
        let (sut, sound, attention, _) = makeSUT()

        sut.notify(.shortBreakEnded)
        sut.notify(.longBreakEnded)

        XCTAssertEqual(sound.playCount, 2)
        XCTAssertEqual(attention.requestCount, 2)
    }

    /// App bloqueado dispara várias vezes seguidas (o usuário insiste em abrir). Tocar em todas
    /// viraria ruído e ele passaria a ignorar o alerta que importa — o de fim de etapa.
    func test_appBloqueadoEFalhaDeBloqueio_naoTocamSom() {
        let (sut, sound, attention, _) = makeSUT()

        sut.notify(.appBlocked(name: "Slack"))
        sut.notify(.websiteBlockingUnavailable)

        XCTAssertEqual(sound.playCount, 0)
        XCTAssertEqual(attention.requestCount, 0)
    }

    /// O decorador não pode engolir a notificação do sistema — ele acrescenta, não substitui.
    func test_encaminhaTodosOsEventosParaONotificadorDecorado() {
        let (sut, _, _, wrapped) = makeSUT()

        sut.notify(.focusEnded)
        sut.notify(.appBlocked(name: "Slack"))

        XCTAssertEqual(wrapped.events, [.focusEnded, .appBlocked(name: "Slack")])
    }

    func test_isPhaseEnd_classificaCorretamente() {
        XCTAssertTrue(PhaseAlertNotifier.isPhaseEnd(.focusEnded))
        XCTAssertTrue(PhaseAlertNotifier.isPhaseEnd(.shortBreakEnded))
        XCTAssertTrue(PhaseAlertNotifier.isPhaseEnd(.longBreakEnded))
        XCTAssertFalse(PhaseAlertNotifier.isPhaseEnd(.appBlocked(name: "x")))
        XCTAssertFalse(PhaseAlertNotifier.isPhaseEnd(.websiteBlockingUnavailable))
    }
}
