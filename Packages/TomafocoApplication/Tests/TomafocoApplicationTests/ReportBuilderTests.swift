import XCTest
import TomafocoDomain
@testable import TomafocoApplication

/// Testes por tabela do agregador de relatórios (RF-10). Calendário fixo (UTC) e `now` injetado.
final class ReportBuilderTests: XCTestCase {

    private var calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }()

    /// 2026-07-20 00:00 UTC — segunda-feira.
    private let day0 = Date(timeIntervalSince1970: 1_784_505_600)
    private let taskA = UUID(uuidString: "00000000-0000-0000-0000-0000000000AA")!
    private let taskB = UUID(uuidString: "00000000-0000-0000-0000-0000000000BB")!

    private func record(
        day: Int, hour: Int = 9, minutes: Double,
        phase: SessionPhase = .focus, outcome: SessionRecord.Outcome = .completed,
        taskID: UUID? = nil, taskIDs: [UUID]? = nil
    ) -> SessionRecord {
        let start = day0.addingTimeInterval(Double(day) * 86_400 + Double(hour) * 3_600)
        return SessionRecord(
            sessionID: UUID(), phase: phase, startedAt: start,
            endedAt: start.addingTimeInterval(minutes * 60),
            outcome: outcome, cycleNumber: 1, taskIDs: taskIDs ?? (taskID.map { [$0] } ?? [])
        )
    }

    private func task(_ id: UUID, _ title: String) -> FocusTask {
        FocusTask(id: id, title: title, source: .manual, createdAt: day0)
    }

    private func build(
        _ records: [SessionRecord], tasks: [FocusTask] = [],
        interval: DateInterval? = nil, nowDay: Int = 2
    ) -> FocusReport {
        ReportBuilder.build(
            records: records, tasks: tasks, interval: interval,
            now: day0.addingTimeInterval(Double(nowDay) * 86_400 + 43_200), calendar: calendar)
    }

    // MARK: horas por tarefa

    func test_taskTotals_agrupaPorTarefaEOrdenaPorTempoDesc() {
        let report = build([
            record(day: 0, minutes: 25, taskID: taskA),
            record(day: 0, minutes: 25, taskID: taskB),
            record(day: 1, minutes: 25, taskID: taskB)
        ], tasks: [task(taskA, "Estudo"), task(taskB, "Trabalho")])

        XCTAssertEqual(report.taskTotals.map(\.title), ["Trabalho", "Estudo"])
        XCTAssertEqual(report.taskTotals[0].focusTime, 50 * 60)
        XCTAssertEqual(report.taskTotals[0].sessionCount, 2)
    }

    func test_taskTotals_historicoSemTarefa_viraSemTarefa() {
        let report = build([record(day: 0, minutes: 25)])
        XCTAssertEqual(report.taskTotals, [
            FocusReport.TaskTotal(taskID: nil, title: "Sem tarefa", focusTime: 25 * 60, sessionCount: 1)
        ])
    }

    func test_taskTotals_tarefaApagada_naoSomeDoRelatorio() {
        let report = build([record(day: 0, minutes: 25, taskID: taskA)], tasks: [])
        XCTAssertEqual(report.taskTotals[0].title, "Tarefa removida")
    }

    /// Foco multi-tarefa (RF-09.4): uma sessão com N tarefas dá o tempo CHEIO a cada uma.
    func test_taskTotals_multitarefa_tempoCheioParaCadaTarefa() {
        let report = build([
            record(day: 0, minutes: 25, taskIDs: [taskA, taskB])
        ], tasks: [task(taskA, "Estudo"), task(taskB, "Trabalho")])

        XCTAssertEqual(report.taskTotals.count, 2)
        XCTAssertEqual(report.taskTotals[0].focusTime, 25 * 60)
        XCTAssertEqual(report.taskTotals[1].focusTime, 25 * 60)
        XCTAssertEqual(report.taskTotals.map(\.sessionCount), [1, 1])
        // O total geral não infla: continua contando por sessão.
        XCTAssertEqual(report.summary.focusTotal, 25 * 60)
    }

    func test_taskTotals_intervalosNaoContam() {
        let report = build([
            record(day: 0, minutes: 25, taskID: taskA),
            record(day: 0, minutes: 5, phase: .shortBreak, taskID: taskA)
        ], tasks: [task(taskA, "Estudo")])
        XCTAssertEqual(report.taskTotals[0].focusTime, 25 * 60)
    }

    // MARK: totais diários

    func test_dailyTotals_separaFocoEIntervaloPorDia() {
        let report = build([
            record(day: 0, minutes: 25),
            record(day: 0, minutes: 5, phase: .shortBreak),
            record(day: 0, minutes: 25),
            record(day: 1, minutes: 15, phase: .longBreak)
        ])

        XCTAssertEqual(report.dailyTotals, [
            FocusReport.DailyTotal(day: day0, focusTime: 50 * 60, breakTime: 5 * 60, breakCount: 1),
            FocusReport.DailyTotal(day: day0.addingTimeInterval(86_400), focusTime: 0,
                                   breakTime: 15 * 60, breakCount: 1)
        ])
    }

    /// Sessão que cruza a meia-noite conta inteira no dia em que COMEÇOU.
    func test_dailyTotals_sessaoCruzandoMeiaNoite_contaNoDiaDeInicio() {
        let report = build([record(day: 0, hour: 23, minutes: 90)])
        XCTAssertEqual(report.dailyTotals.count, 1)
        XCTAssertEqual(report.dailyTotals[0].day, day0)
        XCTAssertEqual(report.dailyTotals[0].focusTime, 90 * 60)
    }

    // MARK: filtro de período

    func test_interval_filtraPorInicioDaSessao() {
        let onlyDay1 = DateInterval(start: day0.addingTimeInterval(86_400), duration: 86_400)
        let report = build([
            record(day: 0, minutes: 25, taskID: taskA),
            record(day: 1, minutes: 25, taskID: taskA)
        ], tasks: [task(taskA, "Estudo")], interval: onlyDay1)

        XCTAssertEqual(report.summary.focusTotal, 25 * 60)
        XCTAssertEqual(report.dailyTotals.count, 1)
    }

    // MARK: resumo

    func test_summary_contaDesfechosSoDeFoco() {
        let report = build([
            record(day: 0, minutes: 25, outcome: .completed),
            record(day: 0, minutes: 10, outcome: .cancelled),
            record(day: 0, minutes: 12, outcome: .skipped),
            record(day: 0, minutes: 5, phase: .shortBreak, outcome: .cancelled)
        ])
        XCTAssertEqual(report.summary.completedFocusCount, 1)
        XCTAssertEqual(report.summary.cancelledFocusCount, 1)
        XCTAssertEqual(report.summary.skippedFocusCount, 1)
    }

    func test_summary_mediaDiaria_ignoraDiasSemFoco() {
        let report = build([
            record(day: 0, minutes: 30),
            record(day: 2, minutes: 60)
        ])
        XCTAssertEqual(report.summary.dailyFocusAverage, 45 * 60)
    }

    func test_streak_diasConsecutivosAtehoje() {
        let report = build([
            record(day: 0, minutes: 25),
            record(day: 1, minutes: 25),
            record(day: 2, minutes: 25)
        ], nowDay: 2)
        XCTAssertEqual(report.summary.streakDays, 3)
    }

    /// Hoje ainda sem foco não zera a sequência — ela é medida até ontem.
    func test_streak_hojeSemFoco_contaAtehOntem() {
        let report = build([
            record(day: 0, minutes: 25),
            record(day: 1, minutes: 25)
        ], nowDay: 2)
        XCTAssertEqual(report.summary.streakDays, 2)
    }

    func test_streak_buracoOntem_zera() {
        let report = build([record(day: 0, minutes: 25)], nowDay: 2)
        XCTAssertEqual(report.summary.streakDays, 0)
    }

    /// A sequência olha o histórico COMPLETO: filtrar "só hoje" não encolhe uma sequência real.
    func test_streak_ignoraFiltroDePeriodo() {
        let onlyDay2 = DateInterval(start: day0.addingTimeInterval(2 * 86_400), duration: 86_400)
        let report = build([
            record(day: 0, minutes: 25),
            record(day: 1, minutes: 25),
            record(day: 2, minutes: 25)
        ], interval: onlyDay2, nowDay: 2)
        XCTAssertEqual(report.summary.streakDays, 3)
        XCTAssertEqual(report.summary.focusTotal, 25 * 60)
    }

    // MARK: histórico das tarefas (FEAT-001)

    /// Helper: tarefa com entradas de histórico em dias relativos a `day0`.
    private func task(_ id: UUID, _ title: String, historyDays: [Int]) -> FocusTask {
        let entries = historyDays.map {
            TaskHistoryEntry(
                id: UUID(),
                createdAt: day0.addingTimeInterval(Double($0) * 86_400 + 36_000),
                text: "entrada d\($0)")
        }
        return FocusTask(id: id, title: title, source: .manual, createdAt: day0, history: entries)
    }

    func test_historico_maisRecentePrimeiroComTituloResolvido() {
        let report = build([], tasks: [
            task(taskA, "Alpha", historyDays: [0, 2]),
            task(taskB, "Beta", historyDays: [1])
        ])
        XCTAssertEqual(report.historyEntries.map(\.text), ["entrada d2", "entrada d1", "entrada d0"])
        XCTAssertEqual(report.historyEntries.map(\.taskTitle), ["Alpha", "Beta", "Alpha"])
        XCTAssertEqual(report.historyEntries.first?.taskID, taskA)
    }

    func test_historico_recortaPeloIntervalo() {
        let onlyDay2 = DateInterval(start: day0.addingTimeInterval(2 * 86_400), duration: 86_400)
        let report = build([], tasks: [task(taskA, "Alpha", historyDays: [0, 1, 2])], interval: onlyDay2)
        XCTAssertEqual(report.historyEntries.map(\.text), ["entrada d2"])
    }

    func test_historico_tarefaSemEntradas_naoPolui() {
        let report = build([], tasks: [task(taskA, "Alpha"), task(taskB, "Beta", historyDays: [1])])
        XCTAssertEqual(report.historyEntries.count, 1)
        XCTAssertEqual(report.historyEntries.first?.taskTitle, "Beta")
    }

    func test_vazio_tudoZerado() {
        let report = build([])
        XCTAssertTrue(report.taskTotals.isEmpty)
        XCTAssertTrue(report.dailyTotals.isEmpty)
        XCTAssertEqual(report.summary.focusTotal, 0)
        XCTAssertEqual(report.summary.streakDays, 0)
        XCTAssertEqual(report.summary.dailyFocusAverage, 0)
        XCTAssertTrue(report.historyEntries.isEmpty)
    }
}
