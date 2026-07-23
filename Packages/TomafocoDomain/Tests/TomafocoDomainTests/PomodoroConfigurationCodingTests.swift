import XCTest
@testable import TomafocoDomain

/// `blockedRedirectURL` é novo — config gravada antes dele precisa decodificar com `nil`,
/// sem apagar as outras preferências (o store cai no padrão se a decodificação falhar).
final class PomodoroConfigurationCodingTests: XCTestCase {

    func test_configAntigaSemRedirect_decodificaComNil() throws {
        let json = """
        {"focusDuration":1500,"shortBreakDuration":300,"longBreakDuration":900,
         "cyclesBeforeLongBreak":4,"autoStartNextFocus":false,"forceTerminateApps":false,
         "hardcore":{"isEnabled":false,"minimumMinutesBeforeCancel":5,"requireReason":true}}
        """
        let config = try JSONDecoder().decode(PomodoroConfiguration.self, from: Data(json.utf8))
        XCTAssertNil(config.blockedRedirectURL)
        XCTAssertEqual(config.focusDuration, 1500)
    }

    func test_configAntigaSemSyncReminder_decodificaComPadraoLigado() throws {
        // Sem a chave `syncReminderCompletion` (config anterior ao campo) → padrão true,
        // e as demais preferências continuam intactas (não cai tudo para o padrão).
        let json = """
        {"focusDuration":1500,"shortBreakDuration":300,"longBreakDuration":900,
         "cyclesBeforeLongBreak":4,"autoStartNextFocus":false,"forceTerminateApps":false,
         "hardcore":{"isEnabled":false,"minimumMinutesBeforeCancel":5,"requireReason":true}}
        """
        let config = try JSONDecoder().decode(PomodoroConfiguration.self, from: Data(json.utf8))
        XCTAssertTrue(config.syncReminderCompletion)
        XCTAssertEqual(config.focusDuration, 1500)
    }

    func test_roundtripComSyncReminderDesligado_preserva() throws {
        var config = PomodoroConfiguration()
        config.syncReminderCompletion = false
        let decoded = try JSONDecoder().decode(
            PomodoroConfiguration.self, from: JSONEncoder().encode(config))
        XCTAssertFalse(decoded.syncReminderCompletion)
    }

    func test_roundtripComRedirect_preserva() throws {
        var config = PomodoroConfiguration()
        config.blockedRedirectURL = "https://example.com"
        let decoded = try JSONDecoder().decode(
            PomodoroConfiguration.self, from: JSONEncoder().encode(config))
        XCTAssertEqual(decoded.blockedRedirectURL, "https://example.com")
    }
}
