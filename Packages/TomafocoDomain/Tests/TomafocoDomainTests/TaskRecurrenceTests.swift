import XCTest
@testable import TomafocoDomain

/// Repetição customizada (RF-09.21): próxima data por regra, normalização, Codable e legado da
/// diária. "Hoje" = sexta 27/11/2026.
final class TaskRecurrenceTests: XCTestCase {

    private var calendar: Calendar!

    override func setUp() {
        super.setUp()
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Sao_Paulo")!
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 10, _ min: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    private func next(_ rule: TaskRecurrence, from now: Date) -> Date {
        rule.nextDay(after: now, calendar: calendar)
    }

    private var friday: Date { date(2026, 11, 27) }

    func test_diaria_eACadaNDias() {
        XCTAssertEqual(next(.everyDay, from: friday), date(2026, 11, 28, 0))
        XCTAssertEqual(next(.daily(interval: 3), from: friday), date(2026, 11, 30, 0))
    }

    func test_diasUteis_sextaVaiParaSegunda() {
        XCTAssertEqual(next(.weekdays, from: friday), date(2026, 11, 30, 0))
        XCTAssertEqual(next(.weekdays, from: date(2026, 11, 30)), date(2026, 12, 1, 0))
    }

    func test_finsDeSemana() {
        XCTAssertEqual(next(.weekends, from: friday), date(2026, 11, 28, 0))
        XCTAssertEqual(next(.weekends, from: date(2026, 11, 28)), date(2026, 11, 29, 0))
        XCTAssertEqual(next(.weekends, from: date(2026, 11, 29)), date(2026, 12, 5, 0))
    }

    func test_semanal_diasEscolhidos_eACadaDuasSemanas() {
        XCTAssertEqual(next(.weekly(weekdays: [6], interval: 1), from: friday), date(2026, 12, 4, 0))
        // Segunda a cada 2 semanas, contando da semana da conclusão: pula a segunda 30/11.
        XCTAssertEqual(next(.weekly(weekdays: [2], interval: 2), from: friday), date(2026, 12, 7, 0))
        // Mesma semana ainda vale: segunda → quarta da mesma semana.
        XCTAssertEqual(next(.weekly(weekdays: [2, 4], interval: 2), from: date(2026, 11, 30)), date(2026, 12, 2, 0))
    }

    func test_mensal_diaDoMes_ultimoDiaQuandoNaoExiste_eIntervalo() {
        XCTAssertEqual(next(.monthly(day: 30, interval: 1), from: friday), date(2026, 11, 30, 0))
        XCTAssertEqual(next(.monthly(day: 15, interval: 1), from: friday), date(2026, 12, 15, 0))
        XCTAssertEqual(next(.monthly(day: 27, interval: 1), from: friday), date(2026, 12, 27, 0), "hoje não conta")
        XCTAssertEqual(next(.monthly(day: 31, interval: 1), from: friday), date(2026, 11, 30, 0), "novembro tem 30")
        XCTAssertEqual(next(.monthly(day: 31, interval: 1), from: date(2026, 11, 30)), date(2026, 12, 31, 0))
        XCTAssertEqual(next(.monthly(day: 31, interval: 1), from: date(2027, 1, 31)), date(2027, 2, 28, 0))
        XCTAssertEqual(next(.monthly(day: 15, interval: 3), from: friday), date(2027, 2, 15, 0))
    }

    func test_anual_e29DeFevereiro() {
        XCTAssertEqual(next(.yearly(month: 12, day: 25), from: friday), date(2026, 12, 25, 0))
        XCTAssertEqual(next(.yearly(month: 11, day: 27), from: friday), date(2027, 11, 27, 0))
        XCTAssertEqual(next(.yearly(month: 2, day: 29), from: friday), date(2027, 2, 28, 0))
    }

    func test_normalized() {
        XCTAssertEqual(TaskRecurrence.daily(interval: 0).normalized, .daily(interval: 1))
        XCTAssertEqual(TaskRecurrence.daily(interval: 500).normalized, .daily(interval: 99))
        XCTAssertEqual(TaskRecurrence.weekly(weekdays: [9, 2, 2, 0], interval: 1).normalized,
                       .weekly(weekdays: [2], interval: 1))
        XCTAssertEqual(TaskRecurrence.weekly(weekdays: [], interval: 1).normalized,
                       .weekly(weekdays: [1, 2, 3, 4, 5, 6, 7], interval: 1))
        XCTAssertEqual(TaskRecurrence.monthly(day: 40, interval: 1).normalized, .monthly(day: 31, interval: 1))
        XCTAssertEqual(TaskRecurrence.yearly(month: 13, day: 0).normalized, .yearly(month: 12, day: 1))
    }

    // MARK: - Tarefa

    func test_vencimentoDoClone_mantemHorario_semVencimento2359() {
        var task = FocusTask(id: UUID(), title: "T", source: .manual, createdAt: friday,
                             dueDate: date(2026, 11, 27, 8, 30), recurrence: .weekdays)
        XCTAssertEqual(task.nextOccurrenceDueDate(now: friday, calendar: calendar), date(2026, 11, 30, 8, 30))
        task.dueDate = nil
        XCTAssertEqual(task.nextOccurrenceDueDate(now: friday, calendar: calendar), date(2026, 11, 30, 23, 59))
    }

    func test_clone_levaAMesmaRegra() {
        let rule = TaskRecurrence.monthly(day: 5, interval: 2)
        let task = FocusTask(id: UUID(), title: "T", source: .manual, createdAt: friday, recurrence: rule)
        let clone = task.nextOccurrence(id: UUID(), now: friday, calendar: calendar)
        XCTAssertEqual(clone.recurrence, rule)
        XCTAssertEqual(clone.dueDate, date(2027, 1, 5, 23, 59))
    }

    func test_repeatsDaily_atalho() {
        var task = FocusTask(id: UUID(), title: "T", source: .manual, createdAt: friday, repeatsDaily: true)
        XCTAssertEqual(task.recurrence, .everyDay)
        task.recurrence = .weekends
        task.repeatsDaily = true
        XCTAssertEqual(task.recurrence, .weekends, "ligar de novo não troca a regra")
        task.repeatsDaily = false
        XCTAssertNil(task.recurrence)
    }

    // MARK: - Codable

    func test_codable_roundtripTodosOsTipos() throws {
        for rule in [TaskRecurrence.daily(interval: 2), .weekdays, .weekly(weekdays: [3], interval: 4),
                     .monthly(day: 31, interval: 1), .yearly(month: 2, day: 29)] {
            let task = FocusTask(id: UUID(), title: "T", source: .manual, createdAt: friday, recurrence: rule)
            let decoded = try JSONDecoder().decode(FocusTask.self, from: JSONEncoder().encode(task))
            XCTAssertEqual(decoded.recurrence, rule)
        }
    }

    /// Tarefa gravada antes do RF-09.21 só tem `repeatsDaily` — `true` vira todo dia.
    func test_decode_legadoRepeatsDaily() throws {
        let base = #""id":"00000000-0000-0000-0000-0000000000AB","title":"T","source":"manual","createdAt":0"#
        let daily = try JSONDecoder().decode(FocusTask.self, from: Data("{\(base),\"repeatsDaily\":true}".utf8))
        let plain = try JSONDecoder().decode(FocusTask.self, from: Data("{\(base),\"repeatsDaily\":false}".utf8))
        let none = try JSONDecoder().decode(FocusTask.self, from: Data("{\(base)}".utf8))
        XCTAssertEqual(daily.recurrence, .everyDay)
        XCTAssertNil(plain.recurrence)
        XCTAssertNil(none.recurrence)
    }

    func test_decode_tipoDesconhecido_viraDiaria() throws {
        let rule = try JSONDecoder().decode(TaskRecurrence.self, from: Data(#"{"kind":"lunar","interval":2}"#.utf8))
        XCTAssertEqual(rule, .daily(interval: 2))
    }
}
