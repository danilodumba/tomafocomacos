import XCTest
@testable import TomafocoDomain

/// Filtro por vencimento (FEAT-005, RF-09.11): hoje / próximos 7 dias / atrasadas.
final class TaskDueFilterTests: XCTestCase {

    private var calendar: Calendar!
    private var now: Date!

    override func setUp() {
        super.setUp()
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Sao_Paulo")!
        now = date(27, 10)
    }

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    private func task(due: Date?, completed: Bool = false) -> FocusTask {
        FocusTask(id: UUID(), title: "T", source: .manual, createdAt: date(1, 9),
                  completedAt: completed ? date(27, 8) : nil, dueDate: due)
    }

    private func matches(_ filter: TaskDueFilter, _ task: FocusTask) -> Bool {
        filter.matches(task, now: now, calendar: calendar)
    }

    func test_all_incluiSemVencimento() {
        XCTAssertTrue(matches(.all, task(due: nil)))
    }

    func test_semVencimento_soEmAll() {
        for filter in [TaskDueFilter.today, .next7Days, .overdue] {
            XCTAssertFalse(matches(filter, task(due: nil)), "\(filter)")
        }
    }

    func test_today_diaInteiro_inclusiveJaVencidaHoje() {
        XCTAssertTrue(matches(.today, task(due: date(27, 0, 0))))
        XCTAssertTrue(matches(.today, task(due: date(27, 23, 59))))
        XCTAssertFalse(matches(.today, task(due: date(28, 0, 0))))
    }

    /// FEAT-006, problema 1: "Hoje" é a lista do que tem de ser feito hoje — inclui as abertas
    /// atrasadas de dias anteriores.
    func test_today_incluiAtrasadasAbertasDeDiasAnteriores() {
        XCTAssertTrue(matches(.today, task(due: date(26, 23, 59))))
        XCTAssertTrue(matches(.today, task(due: date(1, 9))))
    }

    /// Concluída de ontem não está "pendente hoje".
    func test_today_naoIncluiConcluidaDeDiaAnterior() {
        XCTAssertFalse(matches(.today, task(due: date(26, 23, 59), completed: true)))
        // Concluída que vence hoje continua aparecendo (comportamento anterior).
        XCTAssertTrue(matches(.today, task(due: date(27, 18), completed: true)))
    }

    /// H4: vencimento gravado em UTC (00:00Z = 21:00 do dia anterior em São Paulo) é avaliado no
    /// fuso do calendário — é "hoje" à noite, não amanhã, e não está atrasado de manhã.
    func test_fuso_vencimentoUTCMeiaNoite_eHojeANoiteNoFusoLocal() {
        let utcMidnight = ISO8601DateFormatter().date(from: "2026-10-28T00:00:00Z")! // 27/10 21:00 -03
        XCTAssertTrue(matches(.today, task(due: utcMidnight)))
        XCTAssertFalse(matches(.overdue, task(due: utcMidnight)))
    }

    func test_next7Days_deHojeAteFimDoSetimoDia() {
        XCTAssertTrue(matches(.next7Days, task(due: date(27, 8))))
        XCTAssertTrue(matches(.next7Days, task(due: date(31, 23, 0))))
        XCTAssertTrue(calendar.date(byAdding: .day, value: 7, to: date(27, 23, 59)).map {
            matches(.next7Days, task(due: $0))
        } ?? false)
        let eighthDay = calendar.date(byAdding: .day, value: 8, to: calendar.startOfDay(for: now))!
        XCTAssertFalse(matches(.next7Days, task(due: eighthDay)))
    }

    /// "Próximos 7 dias" contém "Hoje": as abertas atrasadas entram; concluída de ontem não.
    func test_next7Days_incluiAtrasadasAbertas_comoHoje() {
        XCTAssertTrue(matches(.next7Days, task(due: date(26, 23))))
        XCTAssertTrue(matches(.next7Days, task(due: date(1, 9))))
        XCTAssertFalse(matches(.next7Days, task(due: date(26, 23), completed: true)))
        XCTAssertTrue(matches(.next7Days, task(due: date(27, 18), completed: true)))
    }

    func test_overdue_abertaComVencimentoPassado() {
        XCTAssertTrue(matches(.overdue, task(due: date(27, 9, 59))))
        XCTAssertTrue(matches(.overdue, task(due: date(1, 9))))
        XCTAssertFalse(matches(.overdue, task(due: date(27, 10, 1))))
        XCTAssertFalse(matches(.overdue, task(due: date(1, 9), completed: true)))
    }
}
