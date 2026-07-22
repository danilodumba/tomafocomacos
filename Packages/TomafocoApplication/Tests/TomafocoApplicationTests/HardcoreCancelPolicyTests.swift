import XCTest
import TomafocoDomain
@testable import TomafocoApplication

final class HardcoreCancelPolicyTests: XCTestCase {

    private let start = Date(timeIntervalSince1970: 1_000_000)

    private func focus(now start: Date) -> PomodoroSession {
        PomodoroSession(id: UUID(), phase: .focus, startedAt: start,
                        endsAt: start.addingTimeInterval(1500), reason: "x", cycleNumber: 1)
    }

    /// `Result<Void, _>` não é `Equatable`, então comparamos pelo caso concreto.
    private func assertSuccess(_ result: Result<Void, DomainError>,
                               file: StaticString = #filePath, line: UInt = #line) {
        if case .failure(let error) = result {
            XCTFail("esperava .success, obteve .failure(\(error))", file: file, line: line)
        }
    }

    private func assertFailure(_ result: Result<Void, DomainError>,
                               _ expected: DomainError,
                               file: StaticString = #filePath, line: UInt = #line) {
        switch result {
        case .success:
            XCTFail("esperava .failure(\(expected)), obteve .success", file: file, line: line)
        case .failure(let error):
            XCTAssertEqual(error, expected, file: file, line: line)
        }
    }

    func test_hardcoreDesligado_permiteSempre() {
        let config = PomodoroConfiguration(hardcore: .init(isEnabled: false))
        let result = HardcoreCancelPolicy.validate(session: focus(now: start), config: config, now: start)
        assertSuccess(result)
    }

    func test_hardcoreLigado_dentroDaCarencia_rejeita() {
        let config = PomodoroConfiguration(hardcore: .init(isEnabled: true, minimumMinutesBeforeCancel: 5))
        // 2 minutos após o início → dentro da carência de 5 min
        let result = HardcoreCancelPolicy.validate(
            session: focus(now: start), config: config, now: start.addingTimeInterval(120))
        assertFailure(result, .cancellationBlockedByHardcore(remainingSeconds: 180))
    }

    func test_hardcoreLigado_aposCarencia_permite() {
        let config = PomodoroConfiguration(hardcore: .init(isEnabled: true, minimumMinutesBeforeCancel: 5))
        let result = HardcoreCancelPolicy.validate(
            session: focus(now: start), config: config, now: start.addingTimeInterval(301))
        assertSuccess(result)
    }

    func test_hardcoreLigado_masNaoEhFoco_permite() {
        let config = PomodoroConfiguration(hardcore: .init(isEnabled: true, minimumMinutesBeforeCancel: 5))
        let br = PomodoroSession(id: UUID(), phase: .shortBreak, startedAt: start,
                                 endsAt: start.addingTimeInterval(300), reason: nil, cycleNumber: 1)
        let result = HardcoreCancelPolicy.validate(session: br, config: config, now: start)
        assertSuccess(result)
    }
}
