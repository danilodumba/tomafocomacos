import Foundation
import Markdown
import TomafocoDomain

/// Transformações de checklist (`- [ ]` / `- [x]`) direto no texto-fonte (FEAT-007).
///
/// Quem diz "isto é item de checklist" é o **parser** (posição do `ListItem` no AST) — não uma
/// regex por linha, que marcaria `[ ]` dentro de bloco de código ou no meio de uma frase. A troca é
/// de um byte só (`' '` ↔ `'x'`), então o resto do texto, finais de linha (LF/CRLF) inclusive,
/// sai idêntico.
public enum MarkdownChecklist {

    /// Inverte o item de checklist que começa em `position`. `nil` se não há item de checklist
    /// ali (o texto mudou por baixo da visualização) — quem chamou não grava nada.
    public static func toggling(itemAt position: MarkdownSourcePosition, in markdown: String) -> String? {
        guard let item = items(in: markdown).first(where: { $0.position == position }) else { return nil }
        var bytes = Array(markdown.utf8)
        let lineStarts = lineStartOffsets(of: bytes)
        guard let offset = checkboxByteOffset(of: item.position, in: bytes, lineStarts: lineStarts) else { return nil }
        bytes[offset] = item.isChecked ? UInt8(ascii: " ") : UInt8(ascii: "x")
        return String(decoding: bytes, as: UTF8.self)
    }

    /// Desmarca todos os itens marcados. Sem item marcado devolve o texto original.
    public static func uncheckingAll(_ markdown: String) -> String {
        let checked = items(in: markdown).filter(\.isChecked)
        guard !checked.isEmpty else { return markdown }
        var bytes = Array(markdown.utf8)
        let lineStarts = lineStartOffsets(of: bytes)
        var changed = false
        for item in checked {
            guard let offset = checkboxByteOffset(of: item.position, in: bytes, lineStarts: lineStarts) else { continue }
            bytes[offset] = UInt8(ascii: " ")
            changed = true
        }
        return changed ? String(decoding: bytes, as: UTF8.self) : markdown
    }

    // MARK: - Privado

    struct Item: Equatable {
        let position: MarkdownSourcePosition
        let isChecked: Bool
    }

    static func items(in markdown: String) -> [Item] {
        var collector = ChecklistCollector()
        collector.visit(Document(parsing: markdown))
        return collector.items
    }

    private struct ChecklistCollector: MarkupWalker {
        var items: [Item] = []

        mutating func visitListItem(_ listItem: ListItem) {
            if let checkbox = listItem.checkbox, let position = MarkdownRenderer.position(of: listItem) {
                items.append(Item(position: position, isChecked: checkbox == .checked))
            }
            descendInto(listItem)
        }
    }

    /// Byte do caractere entre `[` e `]` do item que começa em `position`: pula o marcador
    /// (`-`, `*`, `+` ou `12.`/`12)`) e os espaços, e confere o `[?]` antes de devolver.
    private static func checkboxByteOffset(of position: MarkdownSourcePosition, in bytes: [UInt8],
                                           lineStarts: [Int]) -> Int? {
        guard position.line >= 1, position.line <= lineStarts.count, position.column >= 1 else { return nil }
        var index = lineStarts[position.line - 1] + position.column - 1
        func byte(_ i: Int) -> UInt8? { i < bytes.count ? bytes[i] : nil }

        if let marker = byte(index), [UInt8(ascii: "-"), UInt8(ascii: "*"), UInt8(ascii: "+")].contains(marker) {
            index += 1
        } else {
            let digitsStart = index
            while let b = byte(index), (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(b) { index += 1 }
            guard index > digitsStart, let delimiter = byte(index),
                  delimiter == UInt8(ascii: ".") || delimiter == UInt8(ascii: ")") else { return nil }
            index += 1
        }
        while let b = byte(index), b == UInt8(ascii: " ") || b == UInt8(ascii: "\t") { index += 1 }
        guard byte(index) == UInt8(ascii: "["),
              let mark = byte(index + 1),
              [UInt8(ascii: " "), UInt8(ascii: "x"), UInt8(ascii: "X")].contains(mark),
              byte(index + 2) == UInt8(ascii: "]") else { return nil }
        return index + 1
    }

    /// Offset (em bytes) do início de cada linha. Fim de linha = `\n`, `\r\n` ou `\r` sozinho
    /// (as três formas que o cmark aceita).
    private static func lineStartOffsets(of bytes: [UInt8]) -> [Int] {
        var starts = [0]
        var index = 0
        while index < bytes.count {
            let byte = bytes[index]
            if byte == UInt8(ascii: "\n") {
                starts.append(index + 1)
            } else if byte == UInt8(ascii: "\r") {
                if index + 1 < bytes.count, bytes[index + 1] == UInt8(ascii: "\n") { index += 1 }
                starts.append(index + 1)
            }
            index += 1
        }
        return starts
    }
}

/// Implementação real do port do Domain (clone da diária, P2) — injetada no Composition Root.
public struct MarkdownChecklistResetter: ChecklistResetting {
    public init() {}
    public func uncheckingAll(_ markdown: String) -> String {
        MarkdownChecklist.uncheckingAll(markdown)
    }
}
