import XCTest
@testable import TomafocoDomain

/// Regras puras da tarefa diária (FEAT-004). Fuso fixo para "dia" não depender da máquina.
final class DailyTaskTests: XCTestCase {
    private var calendar: Calendar!

    override func setUp() {
        super.setUp()
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Sao_Paulo")!
    }

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    private func task(repeatsDaily: Bool = true, completedAt: Date?, dueDate: Date? = nil) -> FocusTask {
        FocusTask(id: UUID(), title: "Inglês", source: .manual, createdAt: date(1, 8),
                  completedAt: completedAt, dueDate: dueDate, repeatsDaily: repeatsDaily)
    }

    func test_nextDailyDueDate_comVencimento_amanhaNoMesmoHorario() {
        let next = task(completedAt: nil, dueDate: date(8, 18, 30)).nextDailyDueDate(now: date(10, 9), calendar: calendar)
        XCTAssertEqual(next, date(11, 18, 30))
    }

    func test_nextDailyDueDate_vencimentoFuturo_aindaAmanha() {
        let next = task(completedAt: nil, dueDate: date(20, 7)).nextDailyDueDate(now: date(10, 9), calendar: calendar)
        XCTAssertEqual(next, date(11, 7))
    }

    func test_nextDailyDueDate_semVencimento_amanhaFimDoDia() {
        let next = task(completedAt: nil).nextDailyDueDate(now: date(10, 23, 50), calendar: calendar)
        XCTAssertEqual(next, date(11, 23, 59))
    }
}
