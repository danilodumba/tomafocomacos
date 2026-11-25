import XCTest
import TomafocoDomain
@testable import TomafocoMarkdown

final class MarkdownChecklistTests: XCTestCase {

    private func pos(_ line: Int, _ column: Int) -> MarkdownSourcePosition {
        MarkdownSourcePosition(line: line, column: column)
    }

    func test_toggling_marcaEDesmarca() {
        let text = "- [ ] a\n- [x] b\n"
        XCTAssertEqual(MarkdownChecklist.toggling(itemAt: pos(1, 1), in: text), "- [x] a\n- [x] b\n")
        XCTAssertEqual(MarkdownChecklist.toggling(itemAt: pos(2, 1), in: text), "- [ ] a\n- [ ] b\n")
    }

    func test_toggling_itemAninhado_eListaOrdenada() {
        let text = "1. [ ] pai\n   - [ ] filho\n"
        XCTAssertEqual(MarkdownChecklist.toggling(itemAt: pos(2, 4), in: text), "1. [ ] pai\n   - [x] filho\n")
        XCTAssertEqual(MarkdownChecklist.toggling(itemAt: pos(1, 1), in: text), "1. [x] pai\n   - [ ] filho\n")
    }

    /// Limitação do cmark-gfm: a extensão de checklist não reconhece item dentro de citação — vira
    /// item comum com o texto "[ ] x". Renderer e toggle concordam (nada clicável, nada alterado).
    func test_checklistDentroDeCitacao_naoEReconhecido() {
        let text = "> ação\n> - [ ] x\n"
        let blocks = MarkdownRenderer.blocks(from: text)
        guard case let .quote(inner) = blocks.first, case let .list(list) = inner.last,
              let item = list.items.first, let position = item.position else { return XCTFail() }
        XCTAssertNil(item.checkbox)
        XCTAssertNil(MarkdownChecklist.toggling(itemAt: position, in: text))
        XCTAssertEqual(MarkdownChecklist.uncheckingAll("> - [x] x\n"), "> - [x] x\n")
    }

    func test_toggling_posicaoDoRendererBateComOTexto() {
        // Acentos antes do item: a coluna do cmark é em bytes, a conversão tem que bater.
        let text = "Introdução çá\n\n* [ ] um\n+ [X] dois\n"
        let blocks = MarkdownRenderer.blocks(from: text)
        var result = text
        for block in blocks {
            guard case let .list(list) = block else { continue }
            for item in list.items {
                result = MarkdownChecklist.toggling(itemAt: item.position!, in: result)!
            }
        }
        XCTAssertEqual(result, "Introdução çá\n\n* [x] um\n+ [ ] dois\n")
    }

    func test_toggling_naoMexeEmBlocoDeCodigo() {
        let text = "```\n- [ ] dentro\n```\n- [ ] fora\n"
        XCTAssertNil(MarkdownChecklist.toggling(itemAt: pos(2, 1), in: text))
        XCTAssertEqual(MarkdownChecklist.toggling(itemAt: pos(4, 1), in: text), "```\n- [ ] dentro\n```\n- [x] fora\n")
    }

    func test_toggling_linhaQueNaoEChecklist_nil() {
        XCTAssertNil(MarkdownChecklist.toggling(itemAt: pos(1, 1), in: "- item comum\n"))
        XCTAssertNil(MarkdownChecklist.toggling(itemAt: pos(9, 1), in: "- [ ] a\n"))
    }

    func test_toggling_preservaCRLF() {
        let text = "- [ ] a\r\n- [ ] b\r\n"
        XCTAssertEqual(MarkdownChecklist.toggling(itemAt: pos(2, 1), in: text), "- [ ] a\r\n- [x] b\r\n")
    }

    func test_uncheckingAll() {
        let text = "# Rotina\n\n- [x] a\n- [ ] b\n  - [X] c\n\n```\n- [x] código\n```\n"
        XCTAssertEqual(MarkdownChecklist.uncheckingAll(text),
                       "# Rotina\n\n- [ ] a\n- [ ] b\n  - [ ] c\n\n```\n- [x] código\n```\n")
    }

    func test_uncheckingAll_semMarcados_devolveOriginal() {
        let text = "- [ ] a\n"
        XCTAssertEqual(MarkdownChecklist.uncheckingAll(text), text)
        XCTAssertEqual(MarkdownChecklistResetter().uncheckingAll("- [x] a"), "- [ ] a")
    }
}
