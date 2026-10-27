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

    // MARK: histórico (FEAT-001)

    func test_historicoCSV_cabecalhoEUmaLinhaPorEntrada() {
        let entries = [
            FocusReport.HistoryItem(id: UUID(), taskID: UUID(), taskTitle: "Cliente", date: day, text: "liguei"),
            FocusReport.HistoryItem(id: UUID(), taskID: UUID(), taskTitle: "Boleto", date: day, text: "paguei")
        ]
        let csv = ReportCSVExporter.taskHistoryCSV(entries: entries, dateString: fixedDate)
        let lines = csv.components(separatedBy: "\r\n")
        XCTAssertEqual(lines.first, "Tarefa,Data,Descrição")
        XCTAssertEqual(lines[1], "Cliente,2026-07-20 09:00,liguei")
        XCTAssertEqual(lines[2], "Boleto,2026-07-20 09:00,paguei")
    }

    func test_historicoCSV_escapaVirgulaEQuebraDeLinha() {
        let entries = [
            FocusReport.HistoryItem(id: UUID(), taskID: UUID(), taskTitle: "A, B", date: day,
                                    text: "linha 1\nlinha 2")
        ]
        let csv = ReportCSVExporter.taskHistoryCSV(entries: entries, dateString: fixedDate)
        XCTAssertTrue(csv.contains("\"A, B\",2026-07-20 09:00,\"linha 1\nlinha 2\""))
    }

    func test_historicoCSV_semEntradas_soCabecalho() {
        XCTAssertEqual(ReportCSVExporter.taskHistoryCSV(entries: [], dateString: fixedDate),
                       "Tarefa,Data,Descrição")
    }

    // MARK: sessões por tarefa (RF-10.6)

    func test_sessoesCSV_cabecalhoEUmaLinhaPorSessao() {
        let report = TaskReport(
            taskID: UUID(), title: "Pai › Filha", focusTotal: 35 * 60,
            sessions: [
                TaskReport.Session(id: UUID(), startedAt: day, endedAt: day, duration: 25 * 60,
                                   outcome: .completed, subtaskTitle: nil),
                TaskReport.Session(id: UUID(), startedAt: day, endedAt: day, duration: 10 * 60,
                                   outcome: .cancelled, subtaskTitle: "Slides, v2")
            ],
            dailyTotals: [], completions: [], historyEntries: [])
        let csv = ReportCSVExporter.taskSessionsCSV(report: report, dateString: fixedDate)
        let lines = csv.components(separatedBy: "\r\n")
        XCTAssertEqual(lines.first, "Tarefa,Início,Fim,Duração (min),Resultado,Subtarefa")
        XCTAssertEqual(lines[1], "Pai › Filha,2026-07-20 09:00,2026-07-20 09:00,25,Concluída,")
        XCTAssertEqual(lines[2], "Pai › Filha,2026-07-20 09:00,2026-07-20 09:00,10,Cancelada,\"Slides, v2\"")
    }

    private func emptySummary() -> FocusReport.Summary {
        FocusReport.Summary(focusTotal: 0, breakTotal: 0, completedFocusCount: 0,
                            cancelledFocusCount: 0, skippedFocusCount: 0,
                            streakDays: 0, dailyFocusAverage: 0)
    }
}
