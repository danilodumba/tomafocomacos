import Foundation
import XCTest
@testable import TomafocoMarkdown

final class MarkdownRendererTests: XCTestCase {

    private func plain(_ attributed: AttributedString) -> String { String(attributed.characters) }

    func test_titulos_todosOsNiveis() {
        let blocks = MarkdownRenderer.blocks(from: (1...6).map { String(repeating: "#", count: $0) + " T\($0)" }.joined(separator: "\n"))
        XCTAssertEqual(blocks.count, 6)
        for (index, block) in blocks.enumerated() {
            guard case let .heading(level, content) = block else { return XCTFail("esperava título") }
            XCTAssertEqual(level, index + 1)
            XCTAssertEqual(plain(content), "T\(index + 1)")
        }
    }

    func test_paragrafo_quebraSuaveViraEspaco_quebraDuraViraNovaLinha() {
        let blocks = MarkdownRenderer.blocks(from: "um\ndois  \ntrês")
        guard case let .paragraph(content) = blocks.first else { return XCTFail() }
        XCTAssertEqual(plain(content), "um dois\ntrês")
    }

    func test_inline_negritoItalicoTachadoCodigo() {
        guard case let .paragraph(content) = MarkdownRenderer.blocks(from: "**N** _I_ ~~T~~ `C`").first else {
            return XCTFail()
        }
        let intents = content.runs.compactMap { run -> (String, InlinePresentationIntent)? in
            guard let intent = run.inlinePresentationIntent else { return nil }
            return (String(content[run.range].characters), intent)
        }
        XCTAssertEqual(intents.map(\.0), ["N", "I", "T", "C"])
        XCTAssertEqual(intents.map(\.1), [.stronglyEmphasized, .emphasized, .strikethrough, .code])
    }

    func test_inline_negritoDentroDeItalicoAcumula() {
        guard case let .paragraph(content) = MarkdownRenderer.blocks(from: "_a **b**_").first else { return XCTFail() }
        let last = content.runs.last!
        XCTAssertEqual(last.inlinePresentationIntent, [.emphasized, .stronglyEmphasized])
    }

    func test_link_httpsViraLinkClicavel() {
        guard case let .paragraph(content) = MarkdownRenderer.blocks(from: "[site](https://globo.com)").first else {
            return XCTFail()
        }
        XCTAssertEqual(plain(content), "site")
        XCTAssertEqual(content.runs.first?.link, URL(string: "https://globo.com"))
    }

    func test_link_esquemasProibidosViramTexto() {
        for destination in ["javascript:alert(1)", "file:///etc/passwd", "notion://x", "relativo/caminho"] {
            guard case let .paragraph(content) = MarkdownRenderer.blocks(from: "[x](\(destination))").first else {
                return XCTFail()
            }
            XCTAssertEqual(plain(content), "x")
            XCTAssertNil(content.runs.first?.link, destination)
        }
    }

    func test_link_mailtoPermitido() {
        XCTAssertNotNil(MarkdownRenderer.safeURL("mailto:a@b.com"))
        XCTAssertNotNil(MarkdownRenderer.safeURL("HTTP://exemplo.com"))
    }

    func test_imagem_naoBaixa_viraAltClicavel() {
        guard case let .paragraph(content) = MarkdownRenderer.blocks(from: "![logo](https://x.com/a.png)").first else {
            return XCTFail()
        }
        XCTAssertEqual(plain(content), "logo")
        XCTAssertEqual(content.runs.first?.link, URL(string: "https://x.com/a.png"))
    }

    func test_listas_ordenadaComInicio_eAninhada() {
        let blocks = MarkdownRenderer.blocks(from: "3. a\n4. b\n   - c\n")
        guard case let .list(list) = blocks.first else { return XCTFail() }
        XCTAssertTrue(list.isOrdered)
        XCTAssertEqual(list.start, 3)
        XCTAssertEqual(list.items.count, 2)
        guard case let .list(nested) = list.items[1].blocks.last else { return XCTFail("esperava lista aninhada") }
        XCTAssertFalse(nested.isOrdered)
        XCTAssertNil(nested.items[0].checkbox)
    }

    func test_checklist_estadoEPosicao() {
        let blocks = MarkdownRenderer.blocks(from: "- [ ] a\n- [x] b\n- c")
        guard case let .list(list) = blocks.first else { return XCTFail() }
        XCTAssertEqual(list.items.map(\.checkbox), [false, true, nil])
        XCTAssertEqual(list.items[1].position, MarkdownSourcePosition(line: 2, column: 1))
    }

    func test_citacaoAninhada() {
        let blocks = MarkdownRenderer.blocks(from: "> a\n>\n> > b")
        guard case let .quote(inner) = blocks.first else { return XCTFail() }
        XCTAssertEqual(inner.count, 2)
        guard case .quote = inner[1] else { return XCTFail("esperava citação aninhada") }
    }

    func test_codigo_comESemLinguagem() {
        let blocks = MarkdownRenderer.blocks(from: "```swift\nlet a = 1\n```\n\n    recuado\n")
        XCTAssertEqual(blocks.first, .code(language: "swift", text: "let a = 1"))
        XCTAssertEqual(blocks.last, .code(language: nil, text: "recuado"))
    }

    func test_tabela_alinhamentosECelulasCompletadas() {
        let blocks = MarkdownRenderer.blocks(from: "| A | B | C |\n|:--|:-:|--:|\n| 1 | 2 |\n")
        guard case let .table(table) = blocks.first else { return XCTFail("esperava tabela") }
        XCTAssertEqual(table.alignments, [.leading, .center, .trailing])
        XCTAssertEqual(table.header.map(plain), ["A", "B", "C"])
        XCTAssertEqual(table.rows.count, 1)
        XCTAssertEqual(table.rows[0].map(plain), ["1", "2", ""])
    }

    func test_regraHorizontal_eHTMLLiteral() {
        let blocks = MarkdownRenderer.blocks(from: "a\n\n---\n\n<div>oi</div>\n")
        XCTAssertEqual(blocks[1], .thematicBreak)
        XCTAssertEqual(blocks[2], .literal("<div>oi</div>"))
    }

    func test_textoVazio_semBlocos() {
        XCTAssertTrue(MarkdownRenderer.blocks(from: "").isEmpty)
    }
}
