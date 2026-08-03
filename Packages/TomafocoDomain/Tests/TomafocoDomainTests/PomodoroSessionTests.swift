import XCTest
@testable import TomafocoDomain

final class PomodoroSessionTests: XCTestCase {

    private let epoch = Date(timeIntervalSince1970: 1_000_000)

    private func makeFocus(duration: TimeInterval = 25 * 60) -> PomodoroSession {
        PomodoroSession(
            id: UUID(),
            phase: .focus,
            startedAt: epoch,
            endsAt: epoch.addingTimeInterval(duration),
            cycleNumber: 1, taskIDs: []
        )
    }

    func test_remaining_noInicioÉADuraçãoTotal() {
        let s = makeFocus(duration: 1500)
        XCTAssertEqual(s.remaining(now: epoch), 1500, accuracy: 0.001)
    }

    func test_remaining_nuncaFicaNegativo() {
        let s = makeFocus(duration: 100)
        XCTAssertEqual(s.remaining(now: epoch.addingTimeInterval(500)), 0)
    }

    func test_isExpired_antesDoFim_falso() {
        let s = makeFocus(duration: 100)
        XCTAssertFalse(s.isExpired(now: epoch.addingTimeInterval(99)))
    }

    func test_isExpired_exatamenteNoFim_verdadeiro() {
        let s = makeFocus(duration: 100)
        XCTAssertTrue(s.isExpired(now: epoch.addingTimeInterval(100)))
    }

    func test_plannedDuration() {
        XCTAssertEqual(makeFocus(duration: 300).plannedDuration, 300, accuracy: 0.001)
    }

    func test_codable_roundTrip() throws {
        let original = makeFocus()
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PomodoroSession.self, from: data)
        XCTAssertEqual(original, decoded)
    }
}
