import XCTest
import TomafocoDomain
@testable import TomafocoApplication

/// Serialização CSV das tarefas concluídas (RF-10.1 / item 3).
final class ReportCSVExporterTests: XCTestCase {

    private let day = Date(timeIntervalSince1970: 1_000_000)
    private func fixedDate(_ date: Date) -> String { "2026-07-20 09:00" }

    private func total(_ id: UUID, minutes: Double, sessions: Int) -> FocusReport.TaskTotal {
        FocusReport.TaskTotal(taskID: id, title: "x", focusTime: minutes * 60, sessionCount: sessions)
    }

    func test_csv_cabecalhoEUmaLinhaPorTarefa() {
        let id = UUID()
        let task = FocusTask(id: id, title: "Estudo", source: .manual, createdAt: day,
                             completedAt: day, tags: ["swift", "foco"], priority: 1)
        let report = FocusReport(taskTotals: [total(id, minutes: 50, sessions: 2)],
                                 dailyTotals: [], summary: emptySummary())
        let csv = ReportCSVExporter.completedTasksCSV(tasks: [task], report: report, dateString: fixedDate)

        let lines = csv.components(separatedBy: "\r\n")
        XCTAssertEqual(lines.first, "Tarefa,Tags,Prioridade,Tempo de foco (min),Sessões,Concluída em")
        XCTAssertEqual(lines[1], "Estudo,\"swift, foco\",Alta,50,2,2026-07-20 09:00")
    }

    func test_csv_escapaTituloComVirgula() {
        let id = UUID()
        let task = FocusTask(id: id, title: "Ler, revisar", source: .manual, createdAt: day, completedAt: day)
        let report = FocusReport(taskTotals: [], dailyTotals: [], summary: emptySummary())
        let csv = ReportCSVExporter.completedTasksCSV(tasks: [task], report: report, dateString: fixedDate)
        // Sem tempo de foco no relatório → 0 min, 0 sessões; título com vírgula vem entre aspas.
        XCTAssertTrue(csv.contains("\"Ler, revisar\",,Nenhuma,0,0,2026-07-20 09:00"))
    }

    private func emptySummary() -> FocusReport.Summary {
        FocusReport.Summary(focusTotal: 0, breakTotal: 0, completedFocusCount: 0,
                            cancelledFocusCount: 0, skippedFocusCount: 0,
                            streakDays: 0, dailyFocusAverage: 0)
    }
}
