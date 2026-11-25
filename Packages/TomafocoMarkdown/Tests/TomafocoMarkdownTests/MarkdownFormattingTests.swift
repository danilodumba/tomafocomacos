import Foundation
import XCTest
@testable import TomafocoMarkdown

final class MarkdownFormattingTests: XCTestCase {

    private func apply(_ format: MarkdownFormat, _ text: String, _ location: Int, _ length: Int) -> MarkdownEdit {
        MarkdownFormatting.apply(format, to: text, selection: NSRange(location: location, length: length))
    }

    func test_negrito_envolveSelecao() {
        let edit = apply(.bold, "um dois", 3, 4)
        XCTAssertEqual(edit.text, "um **dois**")
        XCTAssertEqual(edit.selection, NSRange(location: 5, length: 4))
    }

    func test_negrito_semSelecao_cursorNoMeio() {
        let edit = apply(.bold, "ab", 1, 0)
        XCTAssertEqual(edit.text, "a****b")
        XCTAssertEqual(edit.selection, NSRange(location: 3, length: 0))
    }

    func test_negrito_tiraQuandoSelecaoEstaDentroDoMarcador() {
        let edit = apply(.bold, "um **dois**", 5, 4)
        XCTAssertEqual(edit.text, "um dois")
        XCTAssertEqual(edit.selection, NSRange(location: 3, length: 4))
    }

    func test_italico_tiraQuandoSelecaoIncluiOMarcador() {
        let edit = apply(.italic, "_oi_", 0, 4)
        XCTAssertEqual(edit.text, "oi")
        XCTAssertEqual(edit.selection, NSRange(location: 0, length: 2))
    }

    func test_codigoETachado() {
        XCTAssertEqual(apply(.code, "x", 0, 1).text, "`x`")
        XCTAssertEqual(apply(.strikethrough, "x", 0, 1).text, "~~x~~")
    }

    func test_link_comSelecao_selecionaOEndereco() {
        let edit = apply(.link, "veja site", 5, 4)
        XCTAssertEqual(edit.text, "veja [site](https://)")
        XCTAssertEqual((edit.text as NSString).substring(with: edit.selection), "https://")
    }

    func test_link_semSelecao_selecionaOTexto() {
        let edit = apply(.link, "", 0, 0)
        XCTAssertEqual(edit.text, "[texto](https://)")
        XCTAssertEqual((edit.text as NSString).substring(with: edit.selection), "texto")
    }

    func test_checklist_variasLinhas_pulaVazias_eTiraDeVolta() {
        let text = "a\n\nb\n"
        let added = apply(.checklist, text, 0, 4)
        XCTAssertEqual(added.text, "- [ ] a\n\n- [ ] b\n")
        let removed = apply(.checklist, added.text, 0, (added.text as NSString).length)
        XCTAssertEqual(removed.text, text)
    }

    func test_checklist_sobreListaTrocaOTipo() {
        XCTAssertEqual(apply(.checklist, "- a", 0, 0).text, "- [ ] a")
        XCTAssertEqual(apply(.bulletList, "- [x] a", 0, 0).text, "- a")
    }

    func test_lista_respeitaRecuo() {
        XCTAssertEqual(apply(.bulletList, "  item", 0, 0).text, "  - item")
    }

    func test_titulo_eCitacao() {
        XCTAssertEqual(apply(.heading, "Plano", 0, 0).text, "## Plano")
        XCTAssertEqual(apply(.heading, "### Plano", 0, 0).text, "Plano")
        XCTAssertEqual(apply(.quote, "frase", 2, 0).text, "> frase")
    }

    func test_titulo_selecaoMista_naoDobraOPrefixo() {
        XCTAssertEqual(apply(.heading, "# A\nB", 0, 5).text, "## A\n## B")
    }

    func test_prefixo_semSelecao_cursorAcompanha() {
        let edit = apply(.bulletList, "x\nabc", 4, 0)
        XCTAssertEqual(edit.text, "x\n- abc")
        XCTAssertEqual(edit.selection, NSRange(location: 6, length: 0))
    }

    func test_selecaoForaDoTexto_eLimitada() {
        let edit = apply(.bold, "ab", 5, 10)
        XCTAssertEqual(edit.text, "ab****")
    }
}
