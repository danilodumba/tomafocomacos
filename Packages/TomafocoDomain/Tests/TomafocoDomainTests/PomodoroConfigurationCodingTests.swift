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

    func test_configAntigaSemMultiTarefa_decodificaDesligado() throws {
        // Sem a chave `allowMultipleTasksInFocus` (config anterior ao campo) → padrão false,
        // sem colapsar o resto da config para o padrão.
        let json = """
        {"focusDuration":1500,"shortBreakDuration":300,"longBreakDuration":900,
         "cyclesBeforeLongBreak":4,"autoStartNextFocus":true,"forceTerminateApps":false,
         "hardcore":{"isEnabled":false,"minimumMinutesBeforeCancel":5,"requireReason":true}}
        """
        let config = try JSONDecoder().decode(PomodoroConfiguration.self, from: Data(json.utf8))
        XCTAssertFalse(config.allowMultipleTasksInFocus)
        XCTAssertTrue(config.autoAdvancePhases)  // demais preferências intactas
    }

    func test_roundtripComMultiTarefaLigado_preserva() throws {
        var config = PomodoroConfiguration()
        config.allowMultipleTasksInFocus = true
        let decoded = try JSONDecoder().decode(
            PomodoroConfiguration.self, from: JSONEncoder().encode(config))
        XCTAssertTrue(decoded.allowMultipleTasksInFocus)
    }

    /// O modo hardcore foi removido, mas a chave continua gravada na configuração de quem já
    /// usava o app. Chave desconhecida tem que ser ignorada em silêncio: se a decodificação
    /// lançasse, o store cairia no padrão e o usuário perderia durações e ajustes sem aviso.
    func test_configComChaveHardcoreObsoleta_ignoraSemPerderOResto() throws {
        let json = """
        {"focusDuration":3000,"shortBreakDuration":300,"longBreakDuration":900,
         "cyclesBeforeLongBreak":3,"autoStartNextFocus":true,"forceTerminateApps":true,
         "hardcore":{"isEnabled":true,"minimumMinutesBeforeCancel":5,"requireReason":true}}
        """
        let config = try JSONDecoder().decode(PomodoroConfiguration.self, from: Data(json.utf8))
        XCTAssertEqual(config.focusDuration, 3000)
        XCTAssertEqual(config.cyclesBeforeLongBreak, 3)
        XCTAssertTrue(config.autoAdvancePhases)
        XCTAssertTrue(config.forceTerminateApps)
    }

    func test_configAntigaSemFlagsDeBloqueioContinuo_decodificaDesligadas() throws {
        let json = """
        {"focusDuration":1200,"shortBreakDuration":300,"longBreakDuration":900,
         "cyclesBeforeLongBreak":4,"autoStartNextFocus":false,"forceTerminateApps":true}
        """
        let config = try JSONDecoder().decode(PomodoroConfiguration.self, from: Data(json.utf8))
        XCTAssertFalse(config.blockAppsWhileRunning)
        XCTAssertFalse(config.blockSitesWhileRunning)
        XCTAssertEqual(config.focusDuration, 1200)
        XCTAssertTrue(config.forceTerminateApps)
    }

    func test_flagsDeBloqueioContinuo_sobrevivemAoRoundTrip() throws {
        let original = PomodoroConfiguration(blockAppsWhileRunning: true, blockSitesWhileRunning: true)
        let data = try JSONEncoder().encode(original)
        XCTAssertEqual(try JSONDecoder().decode(PomodoroConfiguration.self, from: data), original)
    }
}
