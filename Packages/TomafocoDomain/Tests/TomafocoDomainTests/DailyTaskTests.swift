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

    // MARK: - Clone para o dia seguinte

    func test_nextDailyOccurrence_copiaOsCamposEVenceAmanha() {
        let parentID = UUID()
        let original = FocusTask(
            id: UUID(), title: "Inglês", source: .reminders, reminderID: "r1", createdAt: date(1, 8),
            completedAt: date(10, 9), tags: ["estudo"], notes: "Duolingo", dueDate: date(10, 18, 30),
            priority: 1, sourceURL: "https://duolingo.com",
            history: [TaskHistoryEntry(id: UUID(), createdAt: date(5, 8), text: "x")],
            repeatsDaily: true, completionLog: [date(5, 8)], laneID: UUID(), isUrgent: true, parentID: parentID)
        let cloneID = UUID()

        let clone = original.nextDailyOccurrence(id: cloneID, now: date(10, 9), calendar: calendar)

        XCTAssertEqual(clone.id, cloneID)
        XCTAssertEqual(clone.title, "Inglês")
        XCTAssertEqual(clone.source, .reminders)
        XCTAssertEqual(clone.reminderID, "r1")
        XCTAssertEqual(clone.createdAt, date(10, 9))
        XCTAssertNil(clone.completedAt)
        XCTAssertEqual(clone.tags, ["estudo"])
        XCTAssertEqual(clone.notes, "Duolingo")
        XCTAssertEqual(clone.dueDate, date(11, 18, 30))
        XCTAssertEqual(clone.priority, 1)
        XCTAssertEqual(clone.sourceURL, "https://duolingo.com")
        XCTAssertTrue(clone.repeatsDaily)
        XCTAssertTrue(clone.isUrgent)
        XCTAssertEqual(clone.parentID, parentID)
    }

    func test_nextDailyOccurrence_naoHerdaHistoricoLogNemRaia() {
        let original = FocusTask(
            id: UUID(), title: "Inglês", source: .manual, createdAt: date(1, 8), completedAt: date(10, 9),
            history: [TaskHistoryEntry(id: UUID(), createdAt: date(5, 8), text: "x")],
            repeatsDaily: true, completionLog: [date(5, 8)], laneID: UUID())

        let clone = original.nextDailyOccurrence(id: UUID(), now: date(10, 9), calendar: calendar)

        XCTAssertEqual(clone.history, [])
        XCTAssertEqual(clone.completionLog, [])
        XCTAssertNil(clone.laneID)
    }

    func test_nextDailyOccurrence_semVencimento_amanhaFimDoDia() {
        let clone = task(completedAt: date(10, 9)).nextDailyOccurrence(id: UUID(), now: date(10, 9), calendar: calendar)
        XCTAssertEqual(clone.dueDate, date(11, 23, 59))
    }
}
