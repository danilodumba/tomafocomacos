import Foundation
import TomafocoDomain

/// Uma tarefa a criar na criação em lote (RF-09.8): título + campos ajustados no grid.
/// Tags chegam cruas — a normalização é do Domain (`FocusTask.normalizeTags`).
public struct NewTaskDraft: Equatable, Sendable {
    public var title: String
    public var tags: [String]
    public var dueDate: Date?
    public var priority: TaskPriority

    public init(title: String, tags: [String] = [], dueDate: Date? = nil, priority: TaskPriority = .none) {
        self.title = title
        self.tags = tags
        self.dueDate = dueDate
        self.priority = priority
    }
}

/// Converte o texto colado na criação em lote em títulos: 1 linha = 1 tarefa (RF-09.8).
public enum BulkTaskText {

    /// Divide por linha (LF, CRLF ou CR), trima, descarta linhas vazias e tira o marcador de
    /// lista que costuma vir junto ao colar de outro app (`- `, `* `, `• `, `[ ] `, `[x] `, `1. `, `1) `).
    /// Duplicatas NÃO são removidas aqui — o grid as mostra como erro para o usuário decidir.
    public static func parseTitles(_ text: String) -> [String] {
        text.components(separatedBy: .newlines)
            // O espaço extra faz uma linha só com marcador ("- ", trimada para "-") também cair.
            .map { stripListMarker($0.trimmingCharacters(in: .whitespaces) + " ") }
            .filter { !$0.isEmpty }
    }

    private static func stripListMarker(_ line: String) -> String {
        var rest = Substring(line)
        // Checkbox de markdown antes do bullet simples: "- [ ] tarefa".
        if let first = rest.first, "-*•".contains(first), rest.dropFirst().first == " " {
            rest = rest.dropFirst(2)
        }
        for box in ["[ ] ", "[x] ", "[X] "] where rest.hasPrefix(box) {
            rest = rest.dropFirst(box.count)
        }
        // Numeração "1. " / "12) ".
        let digits = rest.prefix { $0.isASCII && $0.isNumber }
        if !digits.isEmpty {
            let afterDigits = rest.dropFirst(digits.count)
            if let sep = afterDigits.first, ".)".contains(sep), afterDigits.dropFirst().first == " " {
                rest = afterDigits.dropFirst(2)
            }
        }
        return rest.trimmingCharacters(in: .whitespaces)
    }
}
