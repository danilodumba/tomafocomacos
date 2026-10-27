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
        XCTAssertFalse(matches(.today, task(due: date(26, 23, 59))))
        XCTAssertFalse(matches(.today, task(due: date(28, 0, 0))))
    }

    func test_next7Days_deHojeAteFimDoSetimoDia() {
        XCTAssertTrue(matches(.next7Days, task(due: date(27, 8))))
        XCTAssertTrue(matches(.next7Days, task(due: date(31, 23, 0))))
        XCTAssertTrue(calendar.date(byAdding: .day, value: 7, to: date(27, 23, 59)).map {
            matches(.next7Days, task(due: $0))
        } ?? false)
        XCTAssertFalse(matches(.next7Days, task(due: date(26, 23))))
        let eighthDay = calendar.date(byAdding: .day, value: 8, to: calendar.startOfDay(for: now))!
        XCTAssertFalse(matches(.next7Days, task(due: eighthDay)))
    }

    func test_overdue_abertaComVencimentoPassado() {
        XCTAssertTrue(matches(.overdue, task(due: date(27, 9, 59))))
        XCTAssertTrue(matches(.overdue, task(due: date(1, 9))))
        XCTAssertFalse(matches(.overdue, task(due: date(27, 10, 1))))
        XCTAssertFalse(matches(.overdue, task(due: date(1, 9), completed: true)))
    }
}
