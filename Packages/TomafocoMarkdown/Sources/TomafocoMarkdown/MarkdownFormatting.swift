import Foundation

/// Ações da barra de formatação do editor (FEAT-007). Puro: recebe texto + seleção (`NSRange` em
/// UTF-16, a unidade do `NSTextView`) e devolve texto + seleção novos.
public enum MarkdownFormat: CaseIterable, Sendable {
    case bold, italic, strikethrough, code, link
    case heading, bulletList, checklist, quote
}

public struct MarkdownEdit: Equatable, Sendable {
    public let text: String
    public let selection: NSRange

    public init(text: String, selection: NSRange) {
        self.text = text
        self.selection = selection
    }
}

public enum MarkdownFormatting {

    public static func apply(_ format: MarkdownFormat, to text: String, selection: NSRange) -> MarkdownEdit {
        let ns = text as NSString
        let selection = clamped(selection, length: ns.length)
        switch format {
        case .bold: return toggleWrap("**", in: ns, selection: selection)
        case .italic: return toggleWrap("_", in: ns, selection: selection)
        case .strikethrough: return toggleWrap("~~", in: ns, selection: selection)
        case .code: return toggleWrap("`", in: ns, selection: selection)
        case .link: return insertLink(in: ns, selection: selection)
        case .heading, .bulletList, .checklist, .quote:
            return toggleLinePrefix(format, in: ns, selection: selection)
        }
    }

    // MARK: - Inline

    /// Seleção já envolvida pelo marcador (por dentro ou por fora) → tira; senão → envolve.
    /// Sem seleção, insere o par e deixa o cursor no meio.
    private static func toggleWrap(_ marker: String, in ns: NSString, selection: NSRange) -> MarkdownEdit {
        let m = (marker as NSString).length
        let selected = ns.substring(with: selection)
        let selectedNS = selected as NSString

        if selectedNS.length >= 2 * m, selected.hasPrefix(marker), selected.hasSuffix(marker) {
            let inner = selectedNS.substring(with: NSRange(location: m, length: selectedNS.length - 2 * m))
            return MarkdownEdit(text: ns.replacingCharacters(in: selection, with: inner),
                                selection: NSRange(location: selection.location, length: (inner as NSString).length))
        }
        let before = NSRange(location: selection.location - m, length: m)
        let after = NSRange(location: NSMaxRange(selection), length: m)
        if before.location >= 0, NSMaxRange(after) <= ns.length,
           ns.substring(with: before) == marker, ns.substring(with: after) == marker {
            let outer = NSRange(location: before.location, length: selection.length + 2 * m)
            return MarkdownEdit(text: ns.replacingCharacters(in: outer, with: selected),
                                selection: NSRange(location: before.location, length: selection.length))
        }
        return MarkdownEdit(text: ns.replacingCharacters(in: selection, with: marker + selected + marker),
                            selection: NSRange(location: selection.location + m, length: selection.length))
    }

    /// `[seleção](https://)` com o endereço selecionado; sem seleção, `[texto](https://)` com
    /// "texto" selecionado.
    private static func insertLink(in ns: NSString, selection: NSRange) -> MarkdownEdit {
        let selected = ns.substring(with: selection)
        let placeholderURL = "https://"
        if selected.isEmpty {
            let label = "texto"
            return MarkdownEdit(text: ns.replacingCharacters(in: selection, with: "[\(label)](\(placeholderURL))"),
                                selection: NSRange(location: selection.location + 1, length: (label as NSString).length))
        }
        let replacement = "[\(selected)](\(placeholderURL))"
        let urlStart = selection.location + 1 + selection.length + 2
        return MarkdownEdit(text: ns.replacingCharacters(in: selection, with: replacement),
                            selection: NSRange(location: urlStart, length: (placeholderURL as NSString).length))
    }

    // MARK: - Por linha

    /// Aplica (ou, se todas as linhas não vazias já têm, tira) o prefixo do bloco nas linhas
    /// tocadas pela seleção. O prefixo entra depois do recuo, para valer em lista aninhada.
    private static func toggleLinePrefix(_ format: MarkdownFormat, in ns: NSString, selection: NSRange) -> MarkdownEdit {
        let lineRange = ns.lineRange(for: selection)
        let block = ns.substring(with: lineRange)
        var lines = block.components(separatedBy: "\n")
        // `lineRange` inclui a quebra final: o último componente vazio não é uma linha.
        let endsWithNewline = block.hasSuffix("\n")
        if endsWithNewline { lines.removeLast() }

        let parsed = lines.map(LinePrefix.init)
        let content = parsed.filter { !$0.rest.trimmingCharacters(in: .whitespaces).isEmpty }
        let removing = !content.isEmpty && content.allSatisfy { $0.has(format) }

        var firstLineDelta = 0
        let rewritten = parsed.enumerated().map { index, line -> String in
            guard !line.rest.trimmingCharacters(in: .whitespaces).isEmpty else { return line.original }
            let newRest = removing ? line.removing(format) : line.adding(format)
            let newLine = line.indent + newRest
            if index == 0 { firstLineDelta = (newLine as NSString).length - (line.original as NSString).length }
            return newLine
        }
        var newBlock = rewritten.joined(separator: "\n")
        if endsWithNewline { newBlock += "\n" }
        let text = ns.replacingCharacters(in: lineRange, with: newBlock)

        let newSelection: NSRange
        if selection.length == 0 {
            newSelection = NSRange(location: max(lineRange.location, selection.location + firstLineDelta), length: 0)
        } else {
            let length = (newBlock as NSString).length - (endsWithNewline ? 1 : 0)
            newSelection = NSRange(location: lineRange.location, length: max(0, length))
        }
        return MarkdownEdit(text: text, selection: newSelection)
    }

    /// Uma linha separada em recuo + resto, com o prefixo de bloco que ela já tem.
    private struct LinePrefix {
        let original: String
        let indent: String
        let rest: String

        init(_ line: String) {
            original = line
            let indentEnd = line.firstIndex { $0 != " " && $0 != "\t" } ?? line.endIndex
            indent = String(line[..<indentEnd])
            rest = String(line[indentEnd...])
        }

        private static let checklistPrefixes = ["- [ ] ", "- [x] ", "- [X] "]

        private var checklistPrefix: String? { Self.checklistPrefixes.first { rest.hasPrefix($0) } }
        private var isBullet: Bool { rest.hasPrefix("- ") && checklistPrefix == nil }
        private var headingPrefixLength: Int? {
            let hashes = rest.prefix { $0 == "#" }.count
            guard (1...6).contains(hashes), rest.dropFirst(hashes).first == " " else { return nil }
            return hashes + 1
        }

        func has(_ format: MarkdownFormat) -> Bool {
            switch format {
            case .heading: return headingPrefixLength != nil
            case .bulletList: return isBullet
            case .checklist: return checklistPrefix != nil
            case .quote: return rest.hasPrefix("> ")
            default: return false
            }
        }

        func removing(_ format: MarkdownFormat) -> String {
            switch format {
            case .heading: return String(rest.dropFirst(headingPrefixLength ?? 0))
            case .bulletList: return String(rest.dropFirst(2))
            case .checklist: return String(rest.dropFirst(checklistPrefix?.count ?? 0))
            case .quote: return String(rest.dropFirst(2))
            default: return rest
            }
        }

        /// Troca o tipo de item em vez de empilhar: lista → checklist vira `- [ ] x`, não `- [ ] - x`.
        func adding(_ format: MarkdownFormat) -> String {
            let bare: String
            if let checklistPrefix { bare = String(rest.dropFirst(checklistPrefix.count)) }
            else if isBullet { bare = String(rest.dropFirst(2)) }
            else { bare = rest }
            switch format {
            // Linha que já é título (seleção mista) troca de nível em vez de virar "## ## A".
            case .heading: return "## " + (headingPrefixLength.map { String(rest.dropFirst($0)) } ?? rest)
            case .bulletList: return "- " + bare
            case .checklist: return "- [ ] " + bare
            case .quote: return "> " + rest
            default: return rest
            }
        }
    }

    private static func clamped(_ range: NSRange, length: Int) -> NSRange {
        let location = min(max(0, range.location), length)
        return NSRange(location: location, length: min(max(0, range.length), length - location))
    }
}
