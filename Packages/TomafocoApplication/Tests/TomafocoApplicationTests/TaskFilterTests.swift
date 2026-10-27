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
}
