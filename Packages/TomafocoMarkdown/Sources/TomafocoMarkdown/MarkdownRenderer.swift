import Foundation
import Markdown

/// Converte markdown (GFM via swift-markdown/cmark-gfm) no modelo de render `MarkdownBlock`.
public enum MarkdownRenderer {

    /// Esquemas que viram link clicável (P5 da FEAT-007). Qualquer outro (`file:`, `javascript:`,
    /// esquema de app, caminho relativo) aparece como texto — clicar num documento não pode abrir
    /// arquivo local nem disparar app.
    public static let allowedLinkSchemes: Set<String> = ["http", "https", "mailto"]

    public static func blocks(from markdown: String) -> [MarkdownBlock] {
        blocks(in: Document(parsing: markdown))
    }

    /// URL clicável para o destino, ou `nil` se o esquema não é permitido.
    public static func safeURL(_ destination: String?) -> URL? {
        guard let destination = destination?.trimmingCharacters(in: .whitespaces),
              let url = URL(string: destination),
              let scheme = url.scheme?.lowercased(),
              allowedLinkSchemes.contains(scheme) else { return nil }
        return url
    }

    // MARK: - Blocos

    private static func blocks(in container: Markup) -> [MarkdownBlock] {
        container.children.flatMap(block(for:))
    }

    private static func block(for markup: Markup) -> [MarkdownBlock] {
        switch markup {
        case let heading as Heading:
            return [.heading(level: heading.level, content: inline(of: heading))]
        case let paragraph as Paragraph:
            return [.paragraph(inline(of: paragraph))]
        case let list as UnorderedList:
            return [.list(MarkdownList(isOrdered: false, start: 1, items: items(of: list)))]
        case let list as OrderedList:
            return [.list(MarkdownList(isOrdered: true, start: Int(list.startIndex), items: items(of: list)))]
        case let quote as BlockQuote:
            return [.quote(blocks(in: quote))]
        case let code as CodeBlock:
            let language = code.language?.trimmingCharacters(in: .whitespaces)
            return [.code(language: language?.isEmpty == false ? language : nil,
                          text: dropTrailingNewline(code.code))]
        case let html as HTMLBlock:
            return [.literal(dropTrailingNewline(html.rawHTML))]
        case is ThematicBreak:
            return [.thematicBreak]
        case let table as Table:
            return [.table(makeTable(table))]
        default:
            // Nó de bloco que não desenhamos (diretivas etc.): mostra o conteúdo que houver.
            return blocks(in: markup)
        }
    }

    private static func items(of list: Markup) -> [MarkdownListItem] {
        list.children.compactMap { child in
            guard let item = child as? ListItem else { return nil }
            let checkbox: Bool? = switch item.checkbox {
            case .checked: true
            case .unchecked: false
            case nil: nil
            }
            return MarkdownListItem(checkbox: checkbox, position: position(of: item), blocks: blocks(in: item))
        }
    }

    static func position(of markup: Markup) -> MarkdownSourcePosition? {
        guard let start = markup.range?.lowerBound else { return nil }
        return MarkdownSourcePosition(line: start.line, column: start.column)
    }

    private static func makeTable(_ table: Table) -> MarkdownTable {
        let header: [AttributedString] = table.head.cells.map { inline(of: $0) }
        let rows: [[AttributedString]] = table.body.rows.map { row in row.cells.map { inline(of: $0) } }
        let columns = max(table.columnAlignments.count, header.count, rows.map(\.count).max() ?? 0)
        let alignments: [MarkdownTable.Alignment] = (0..<columns).map { index in
            guard index < table.columnAlignments.count else { return .leading }
            switch table.columnAlignments[index] {
            case .center: return .center
            case .right: return .trailing
            case .left, nil: return .leading
            }
        }
        func padded(_ cells: [AttributedString]) -> [AttributedString] {
            cells + Array(repeating: AttributedString(), count: max(0, columns - cells.count))
        }
        return MarkdownTable(alignments: alignments, header: padded(header), rows: rows.map(padded))
    }

    private static func dropTrailingNewline(_ text: String) -> String {
        var text = text
        while text.hasSuffix("\n") || text.hasSuffix("\r") { text.removeLast() }
        return text
    }

    // MARK: - Inline

    private static func inline(of container: Markup) -> AttributedString {
        container.children.reduce(into: AttributedString()) { result, child in
            result += inline(child, intent: [], link: nil)
        }
    }

    private static func inline(_ markup: Markup, intent: InlinePresentationIntent, link: URL?) -> AttributedString {
        switch markup {
        case let text as Markdown.Text:
            return styled(text.string, intent: intent, link: link)
        case is SoftBreak:
            return styled(" ", intent: intent, link: link)
        case is LineBreak:
            return styled("\n", intent: intent, link: link)
        case let code as InlineCode:
            return styled(code.code, intent: intent.union(.code), link: link)
        case let html as InlineHTML:
            return styled(html.rawHTML, intent: intent, link: link)
        case is Emphasis:
            return children(of: markup, intent: intent.union(.emphasized), link: link)
        case is Strong:
            return children(of: markup, intent: intent.union(.stronglyEmphasized), link: link)
        case is Strikethrough:
            return children(of: markup, intent: intent.union(.strikethrough), link: link)
        case let anchor as Markdown.Link:
            return children(of: markup, intent: intent, link: safeURL(anchor.destination) ?? link)
        case let image as Markdown.Image:
            // Imagem não é baixada (P5): vira o texto alternativo, clicável se o endereço for
            // seguro. Sem alt, mostra o próprio endereço.
            let alt = image.plainText
            let label = alt.isEmpty ? (image.source ?? "") : alt
            return styled(label, intent: intent, link: safeURL(image.source) ?? link)
        case let symbol as SymbolLink:
            return styled(symbol.destination ?? "", intent: intent.union(.code), link: link)
        default:
            return children(of: markup, intent: intent, link: link)
        }
    }

    private static func children(of markup: Markup, intent: InlinePresentationIntent, link: URL?) -> AttributedString {
        markup.children.reduce(into: AttributedString()) { result, child in
            result += inline(child, intent: intent, link: link)
        }
    }

    private static func styled(_ string: String, intent: InlinePresentationIntent, link: URL?) -> AttributedString {
        var result = AttributedString(string)
        if !intent.isEmpty { result.inlinePresentationIntent = intent }
        if let link { result.link = link }
        return result
    }
}
