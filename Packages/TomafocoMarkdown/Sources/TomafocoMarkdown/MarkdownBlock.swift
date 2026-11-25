import Foundation

/// Modelo de render do documento (FEAT-007): o que a View desenha, já pronto e testado.
///
/// O texto inline é `AttributedString` só com atributos **semânticos** do Foundation
/// (`inlinePresentationIntent` para negrito/itálico/tachado/código e `link`) — fonte, cor e
/// espaçamento são decisão da View (tema claro/escuro, `Brand`).
public enum MarkdownBlock: Equatable, Sendable {
    case heading(level: Int, content: AttributedString)
    case paragraph(AttributedString)
    case list(MarkdownList)
    case quote([MarkdownBlock])
    case code(language: String?, text: String)
    case table(MarkdownTable)
    case thematicBreak
    /// HTML cru: mostrado como texto literal, nunca interpretado (P5).
    case literal(String)
}

public struct MarkdownList: Equatable, Sendable {
    public let isOrdered: Bool
    /// Número do primeiro item (lista ordenada que começa em `3.`); 1 na não ordenada.
    public let start: Int
    public let items: [MarkdownListItem]

    public init(isOrdered: Bool, start: Int, items: [MarkdownListItem]) {
        self.isOrdered = isOrdered
        self.start = start
        self.items = items
    }
}

public struct MarkdownListItem: Equatable, Sendable {
    /// `nil` = item comum; `true`/`false` = item de checklist marcado/desmarcado.
    public let checkbox: Bool?
    /// Onde o item começa no texto — identidade para `MarkdownChecklist.toggling(itemAt:in:)`.
    public let position: MarkdownSourcePosition?
    public let blocks: [MarkdownBlock]

    public init(checkbox: Bool?, position: MarkdownSourcePosition?, blocks: [MarkdownBlock]) {
        self.checkbox = checkbox
        self.position = position
        self.blocks = blocks
    }
}

/// Posição no texto-fonte: linha (1-based) e coluna (1-based, em bytes UTF-8 — a convenção do
/// cmark/swift-markdown).
public struct MarkdownSourcePosition: Hashable, Sendable {
    public let line: Int
    public let column: Int

    public init(line: Int, column: Int) {
        self.line = line
        self.column = column
    }
}

public struct MarkdownTable: Equatable, Sendable {
    public enum Alignment: Equatable, Sendable { case leading, center, trailing }

    /// Uma por coluna (`leading` quando a tabela não define).
    public let alignments: [Alignment]
    public let header: [AttributedString]
    /// Cada linha tem exatamente `alignments.count` células (completadas com vazio).
    public let rows: [[AttributedString]]

    public init(alignments: [Alignment], header: [AttributedString], rows: [[AttributedString]]) {
        self.alignments = alignments
        self.header = header
        self.rows = rows
    }
}
