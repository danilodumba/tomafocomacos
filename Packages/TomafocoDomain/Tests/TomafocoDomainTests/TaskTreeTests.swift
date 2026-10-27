import XCTest
@testable import TomafocoDomain

/// Consultas puras da hierarquia pai → subtarefas (FEAT-003).
final class TaskTreeTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_000)

    private func task(_ title: String, parent: UUID? = nil, done: Bool = false) -> FocusTask {
        FocusTask(id: UUID(), title: title, source: .manual, createdAt: now,
                  completedAt: done ? now : nil, parentID: parent)
    }

    func test_topLevelEChildren() {
        let pai = task("Pai")
        let a = task("A", parent: pai.id)
        let b = task("B", parent: pai.id)
        let outra = task("Outra")
        let all = [a, pai, outra, b]

        XCTAssertEqual(TaskTree.topLevel(all).map(\.title), ["Pai", "Outra"])
        XCTAssertEqual(TaskTree.children(of: pai.id, in: all).map(\.title), ["A", "B"])
        XCTAssertEqual(TaskTree.children(of: outra.id, in: all), [])
    }

    func test_parentEDisplayTitle() {
        let pai = task("Apresentação")
        let filha = task("Revisar", parent: pai.id)
        let orfa = task("Órfã", parent: UUID())
        let all = [pai, filha, orfa]

        XCTAssertEqual(TaskTree.parent(of: filha, in: all)?.id, pai.id)
        XCTAssertNil(TaskTree.parent(of: pai, in: all))
        XCTAssertNil(TaskTree.parent(of: orfa, in: all))
        XCTAssertEqual(TaskTree.displayTitle(of: filha, in: all), "Apresentação › Revisar")
        XCTAssertEqual(TaskTree.displayTitle(of: pai, in: all), "Apresentação")
        // Pai sumiu da lista: o título fica sozinho, sem "nil ›".
        XCTAssertEqual(TaskTree.displayTitle(of: orfa, in: all), "Órfã")
    }

    func test_progress() {
        let pai = task("Pai")
        let all = [pai, task("a", parent: pai.id, done: true), task("b", parent: pai.id)]
        let progress = TaskTree.progress(of: pai.id, in: all)
        XCTAssertEqual(progress.done, 1)
        XCTAssertEqual(progress.total, 2)
        XCTAssertEqual(TaskTree.progress(of: UUID(), in: all).total, 0)
    }

    /// Seletor do timer: pai seguido das filhas, mantendo a ordem relativa de cada grupo.
    func test_grouped_paiSeguidoDasFilhas_ordemRelativaPreservada() {
        let p1 = task("P1")
        let p2 = task("P2")
        let f1a = task("F1a", parent: p1.id)
        let f2 = task("F2", parent: p2.id)
        let f1b = task("F1b", parent: p1.id)
        let orfa = task("Órfã", parent: UUID())
        let all = [f2, p2, f1b, orfa, p1, f1a]

        XCTAssertEqual(TaskTree.grouped(all).map(\.title), ["P2", "F2", "Órfã", "P1", "F1b", "F1a"])
    }
}
