import XCTest
@testable import TomafocoInfrastructure

/// FEAT-006, H2: lembrete "dia inteiro" não pode virar 00:00 (atrasado o dia todo).
final class ReminderDueDateTests: XCTestCase {

    private var calendar: Calendar!

    override func setUp() {
        super.setUp()
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Sao_Paulo")!
    }

    func test_semComponentes_nil() {
        XCTAssertNil(ReminderDueDate.resolve(nil, calendar: calendar))
    }

    func test_diaInteiro_vira2359Local() {
        let date = ReminderDueDate.resolve(DateComponents(year: 2026, month: 10, day: 29), calendar: calendar)
        let expected = calendar.date(from: DateComponents(year: 2026, month: 10, day: 29, hour: 23, minute: 59))
        XCTAssertEqual(date, expected)
    }

    func test_comHora_mantemHorario() {
        let components = DateComponents(year: 2026, month: 10, day: 29, hour: 11, minute: 30)
        let expected = calendar.date(from: components)
        XCTAssertEqual(ReminderDueDate.resolve(components, calendar: calendar), expected)
    }

    func test_comHoraEFusoProprio_respeitaFusoDoLembrete() {
        var components = DateComponents(year: 2026, month: 10, day: 29, hour: 12, minute: 0)
        components.timeZone = TimeZone(identifier: "UTC")
        let expected = ISO8601DateFormatter().date(from: "2026-10-29T12:00:00Z")
        XCTAssertEqual(ReminderDueDate.resolve(components, calendar: calendar), expected)
    }

    func test_semDia_nil() {
        XCTAssertNil(ReminderDueDate.resolve(DateComponents(year: 2026, month: 10), calendar: calendar))
    }
}
