import XCTest
import TomafocoDomain
@testable import TomafocoApplication

/// Conclusões para relatório (RF-10 + FEAT-004).
final class CompletedTaskOccurrenceTests: XCTestCase {
    private func day(_ n: Double) -> Date { Date(timeIntervalSince1970: n * 86_400) }

    func test_tarefaComumConcluida_geraUmaOcorrencia() {
        let task = FocusTask(id: UUID(), title: "Boleto", source: .manual, createdAt: day(0), completedAt: day(1))
        let result = CompletedTaskOccurrence.occurrences(of: [task])
        XCTAssertEqual(result.map(\.task.completedAt), [day(1)])
    }

    func test_tarefaAtivaSemLog_naoAparece() {
        let task = FocusTask(id: UUID(), title: "Boleto", source: .manual, createdAt: day(0))
        XCTAssertTrue(CompletedTaskOccurrence.occurrences(of: [task]).isEmpty)
    }

    func test_diariaConcluidaTresDias_geraTresOcorrenciasMaisRecentePrimeiroComIdsUnicos() {
        let task = FocusTask(id: UUID(), title: "Inglês", source: .manual, createdAt: day(0),
                             completedAt: day(3), repeatsDaily: true, completionLog: [day(1), day(2), day(3)])
        let result = CompletedTaskOccurrence.occurrences(of: [task])
        XCTAssertEqual(result.map(\.task.completedAt), [day(3), day(2), day(1)])
        XCTAssertEqual(Set(result.map(\.id)).count, 3)
    }

    func test_diariaReabertaHoje_mantemConclusoesDoLog() {
        let task = FocusTask(id: UUID(), title: "Inglês", source: .manual, createdAt: day(0),
                             repeatsDaily: true, completionLog: [day(1), day(2)])
        XCTAssertEqual(CompletedTaskOccurrence.occurrences(of: [task]).count, 2)
    }

    func test_csvComOcorrenciasDeDiaria_umaLinhaPorConclusao() {
        let task = FocusTask(id: UUID(), title: "Inglês", source: .manual, createdAt: day(0),
                             repeatsDaily: true, completionLog: [day(1), day(2), day(3)])
        let csv = ReportCSVExporter.completedTasksCSV(
            tasks: CompletedTaskOccurrence.occurrences(of: [task]).map(\.task),
            report: FocusReport(taskTotals: [], dailyTotals: [], summary: .init(
                focusTotal: 0, breakTotal: 0, completedFocusCount: 0, cancelledFocusCount: 0,
                skippedFocusCount: 0, streakDays: 0, dailyFocusAverage: 0)),
            dateString: { _ in "d" })
        XCTAssertEqual(csv.components(separatedBy: "\r\n").count, 4)
    }
}
