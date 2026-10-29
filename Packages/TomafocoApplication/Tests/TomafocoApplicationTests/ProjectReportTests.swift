import XCTest
import TomafocoDomain
@testable import TomafocoApplication

/// Relatório de projeto (RF-10.7): só tarefas pai, foco das filhas somado no pai, total sem
/// contar a mesma sessão duas vezes.
final class ProjectReportTests: XCTestCase {

    private let day0 = Date(timeIntervalSince1970: 1_784_505_600)
    private let project = Project(id: UUID(), title: "Site", createdAt: Date(timeIntervalSince1970: 0))

    private func task(_ title: String, project: UUID? = nil, parent: UUID? = nil, done: Bool = false) -> FocusTask {
        FocusTask(id: UUID(), title: title, source: .manual, createdAt: day0,
                  completedAt: done ? day0 : nil, parentID: parent, projectID: project)
    }

    private func focus(_ minutes: Double, day: Int = 0, _ tasks: FocusTask..., phase: SessionPhase = .focus) -> SessionRecord {
        let start = day0.addingTimeInterval(Double(day) * 86_400)
        return SessionRecord(sessionID: UUID(), phase: phase, startedAt: start,
                             endedAt: start.addingTimeInterval(minutes * 60), outcome: .completed,
                             cycleNumber: 1, taskIDs: tasks.map(\.id))
    }

    private func report(_ records: [SessionRecord], _ tasks: [FocusTask], interval: DateInterval? = nil) -> ProjectReport {
        ReportBuilder.projectReport(project: project, records: records, tasks: tasks, interval: interval)
    }

    func test_soTarefasPaiDoProjeto_ordenadasPorTempo_incluindoSemFoco() {
        let a = task("A", project: project.id)
        let b = task("B", project: project.id)
        let semFoco = task("Sem foco", project: project.id)
        let outra = task("Outro projeto", project: UUID())
        let solta = task("Sem projeto")
        let r = report([focus(25, a), focus(50, b), focus(30, outra), focus(10, solta)], [a, b, semFoco, outra, solta])

        XCTAssertEqual(r.rows.map(\.title), ["B", "A", "Sem foco"])
        XCTAssertEqual(r.rows.map(\.focusTime), [3_000, 1_500, 0])
        XCTAssertEqual(r.focusTotal, 4_500)
        XCTAssertEqual(r.sessionCount, 2)
    }

    func test_focoDaSubtarefa_somaNoPai_eFilhaNaoViraLinha() {
        let pai = task("Pai", project: project.id)
        let filha = task("Filha", project: project.id, parent: pai.id)
        let r = report([focus(25, pai), focus(20, filha)], [pai, filha])

        XCTAssertEqual(r.rows.count, 1)
        XCTAssertEqual(r.rows[0].focusTime, 2_700)
        XCTAssertEqual(r.rows[0].sessionCount, 2)
        XCTAssertEqual(r.rows[0].subtaskCount, 1)
    }

    /// Pai e filha na mesma sessão: uma vez só no pai e no total.
    func test_paiEFilhaNaMesmaSessao_contaUmaVez() {
        let pai = task("Pai", project: project.id)
        let filha = task("Filha", project: project.id, parent: pai.id)
        let r = report([focus(25, pai, filha)], [pai, filha])
        XCTAssertEqual(r.rows[0].focusTime, 1_500)
        XCTAssertEqual(r.focusTotal, 1_500)
    }

    /// Duas tarefas do projeto na mesma sessão: cada linha leva o tempo cheio (regra do relatório
    /// geral), mas o total do projeto conta a sessão uma vez.
    func test_duasTarefasNaMesmaSessao_totalNaoDobra() {
        let a = task("A", project: project.id)
        let b = task("B", project: project.id)
        let r = report([focus(25, a, b)], [a, b])
        XCTAssertEqual(r.rows.map(\.focusTime), [1_500, 1_500])
        XCTAssertEqual(r.focusTotal, 1_500)
        XCTAssertEqual(r.rowsSum, 3_000)
    }

    func test_intervalo_eSoFasesDeFoco() {
        let a = task("A", project: project.id)
        let interval = DateInterval(start: day0.addingTimeInterval(86_400), duration: 86_400)
        let r = report([focus(25, day: 0, a), focus(30, day: 1, a), focus(5, day: 1, a, phase: .shortBreak)], [a],
                       interval: interval)
        XCTAssertEqual(r.focusTotal, 1_800)
        XCTAssertEqual(r.rows[0].sessionCount, 1)
    }

    func test_concluidaAparece_comMarca() {
        let feita = task("Feita", project: project.id, done: true)
        let r = report([focus(10, feita)], [feita])
        XCTAssertEqual(r.rows.first?.isCompleted, true)
    }

    func test_projetoVazio() {
        let r = report([], [])
        XCTAssertEqual(r.rows, [])
        XCTAssertEqual(r.focusTotal, 0)
    }
}
