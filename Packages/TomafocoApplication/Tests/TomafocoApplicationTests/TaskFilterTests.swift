import XCTest
import TomafocoDomain
@testable import TomafocoApplication

/// Recorte compartilhado entre lista e quadro (FEAT-005). Trava a semântica que antes vivia só
/// no `TasksViewModel` (sem target de teste no App).
final class TaskFilterTests: XCTestCase {

    private let calendar = Calendar(identifier: .gregorian)
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func task(_ title: String, tags: [String] = [], priority: Int? = nil, due: Date? = nil) -> FocusTask {
        FocusTask(id: UUID(), title: title, source: .manual, createdAt: now,
                  tags: tags, dueDate: due, priority: priority)
    }

    private func titles(_ filter: TaskFilter, _ tasks: [FocusTask]) -> [String] {
        filter.apply(tasks, now: now, calendar: calendar).map(\.title)
    }

    func test_semCriterio_naoFiltra() {
        XCTAssertEqual(titles(TaskFilter(), [task("a"), task("b")]), ["a", "b"])
    }

    func test_busca_semCaixa_ignoraEspacos() {
        XCTAssertEqual(titles(TaskFilter(searchText: "  DEPLOY "), [task("Fazer deploy"), task("Boleto")]),
                       ["Fazer deploy"])
    }

    /// FEAT-003, lista aninhada: a tarefa de topo entra se ela ou alguma subtarefa casa.
    func test_matchesTree_paiEntraSeFilhaCasa() {
        let pai = task("Apresentação")
        var filha = task("Revisar slides"); filha.parentID = pai.id
        let filter = TaskFilter(searchText: "revisar")
        XCTAssertTrue(filter.matchesTree(pai, children: [filha], now: now, calendar: calendar))
        XCTAssertFalse(filter.matchesTree(pai, children: [], now: now, calendar: calendar))
        XCTAssertFalse(TaskFilter(searchText: "xyz").matchesTree(pai, children: [filha], now: now, calendar: calendar))
    }

    /// FEAT-003, cartão do quadro: a subtarefa passa se ela ou o pai passa.
    func test_matchesCard_filhaPassaPeloPai() {
        let pai = task("Apresentação", tags: ["Trabalho"])
        var filha = task("Revisar"); filha.parentID = pai.id
        let byTag = TaskFilter(tag: "trabalho")
        XCTAssertTrue(byTag.matchesCard(filha, parent: pai, now: now, calendar: calendar))
        XCTAssertFalse(byTag.matchesCard(filha, parent: nil, now: now, calendar: calendar))
        XCTAssertFalse(TaskFilter(searchText: "xyz").matchesCard(filha, parent: pai, now: now, calendar: calendar))
    }

    /// FEAT-006, H1: vencimento é sempre da própria tarefa. Pai atrasado não pode levar para
    /// "Atrasadas" a subtarefa que vence mais tarde hoje (ela apareceria como atrasada sem estar).
    func test_matchesCard_vencimentoNaoPassaPeloPai() {
        let pai = task("Apresentação", due: now.addingTimeInterval(-86_400))
        var filha = task("Revisar", due: now.addingTimeInterval(3_600)); filha.parentID = pai.id
        let overdue = TaskFilter(due: .overdue)
        XCTAssertTrue(overdue.matchesCard(pai, parent: nil, now: now, calendar: calendar))
        XCTAssertFalse(overdue.matchesCard(filha, parent: pai, now: now, calendar: calendar))
    }

    /// Filha SEM vencimento herda o do pai: "Hoje" mostra as subtarefas sem data do pai que
    /// vence hoje (como a lista); filha com data própria no futuro não entra.
    func test_matchesCard_filhaSemVencimento_herdaDoPai() {
        let pai = task("Apresentação", due: now.addingTimeInterval(600))
        var semData = task("Revisar"); semData.parentID = pai.id
        var futura = task("Enviar", due: now.addingTimeInterval(86_400 * 3)); futura.parentID = pai.id
        let today = TaskFilter(due: .today)
        XCTAssertTrue(today.matchesCard(semData, parent: pai, now: now, calendar: calendar))
        XCTAssertFalse(today.matchesCard(futura, parent: pai, now: now, calendar: calendar))
        // Sem pai (tarefa de topo sem data) continua fora de "Hoje".
        XCTAssertFalse(today.matchesCard(task("Solta"), parent: nil, now: now, calendar: calendar))
    }

    /// Herda a data do pai, não a conclusão: filha concluída (sem data) sob pai atrasado não
    /// aparece em "Atrasadas" — igual a uma tarefa de topo concluída.
    func test_matchesCard_filhaConcluidaSemData_naoHerdaAtrasoDoPai() {
        let pai = task("Apresentação", due: now.addingTimeInterval(-86_400))
        var feita = task("Revisar"); feita.parentID = pai.id; feita.completedAt = now.addingTimeInterval(-3_600)
        XCTAssertFalse(TaskFilter(due: .overdue).matchesCard(feita, parent: pai, now: now, calendar: calendar))
        // "Hoje" com pai vencendo hoje: concluída ainda entra (mesma regra da tarefa de topo concluída hoje).
        let paiHoje = task("Apresentação", due: now.addingTimeInterval(600))
        XCTAssertTrue(TaskFilter(due: .today).matchesCard(feita, parent: paiHoje, now: now, calendar: calendar))
    }

    /// Busca/tag/prioridade seguem passando pelo pai, mas o vencimento da filha ainda vale.
    func test_matchesCard_tagPeloPai_vencimentoDaFilha() {
        let pai = task("Apresentação", tags: ["Trabalho"])
        var atrasada = task("Revisar", due: now.addingTimeInterval(-60)); atrasada.parentID = pai.id
        var futura = task("Enviar", due: now.addingTimeInterval(86_400 * 3)); futura.parentID = pai.id
        let filter = TaskFilter(tag: "trabalho", due: .overdue)
        XCTAssertTrue(filter.matchesCard(atrasada, parent: pai, now: now, calendar: calendar))
        XCTAssertFalse(filter.matchesCard(futura, parent: pai, now: now, calendar: calendar))
    }

    func test_tag_semCaixa() {
        XCTAssertEqual(titles(TaskFilter(tag: "trabalho"), [task("a", tags: ["Trabalho"]), task("b", tags: ["Casa"])]),
                       ["a"])
    }

    func test_prioridade_exata_eNenhuma() {
        let tasks = [task("alta", priority: TaskPriority.high.rawPriority), task("sem")]
        XCTAssertEqual(titles(TaskFilter(priority: .high), tasks), ["alta"])
        XCTAssertEqual(titles(TaskFilter(priority: TaskPriority.none), tasks), ["sem"])
    }

    func test_combinaComVencimento() {
        let tasks = [
            task("atrasada trabalho", tags: ["Trabalho"], due: now.addingTimeInterval(-60)),
            task("atrasada casa", tags: ["Casa"], due: now.addingTimeInterval(-60)),
            task("sem data trabalho", tags: ["Trabalho"]),
        ]
        XCTAssertEqual(titles(TaskFilter(tag: "Trabalho", due: .overdue), tasks), ["atrasada trabalho"])
    }

    /// FEAT-006 (RNF performance): recorte de 1.000 tarefas com todos os critérios ligados — o
    /// que a lista refaz a cada render. Medido ~20 ms por 10 passadas (debug, M-series); o limite
    /// é 50× isso — só pega regressão grosseira (ex.: virar O(n²)), não variação de máquina.
    func test_performance_recorteDeMilTarefas() {
        let tags = ["Trabalho", "Casa", "Estudo"]
        let project = UUID()
        let tasks = (0..<1_000).map { i in
            FocusTask(id: UUID(), title: "Tarefa \(i) relatório", source: .manual, createdAt: now,
                      tags: [tags[i % 3]], dueDate: now.addingTimeInterval(Double(i - 500) * 3_600),
                      priority: i % 4 == 0 ? nil : i % 9, projectID: i % 2 == 0 ? project : nil)
        }
        let filter = TaskFilter(searchText: "relat", tag: "trabalho", due: .today, project: .project(project))
        let start = Date()
        for _ in 0..<10 { _ = filter.apply(tasks, now: now, calendar: calendar) }
        XCTAssertLessThan(Date().timeIntervalSince(start), 1.0)
    }
}
