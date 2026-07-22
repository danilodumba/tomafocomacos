import Foundation

/// Value object de um domínio bloqueado. Sempre normalizado: lowercase, sem esquema,
/// sem `www.`, sem caminho, sem porta. A validação acontece na construção (fail fast).
public struct BlockedDomain: Equatable, Codable, Hashable, Sendable {
    public let value: String

    public init(raw: String) throws {
        let normalized = Self.normalize(raw)
        guard Self.isValid(normalized) else { throw DomainError.invalidDomain(raw) }
        self.value = normalized
    }

    /// Remove esquema, `www.`, caminho, query, porta e espaços; aplica lowercase.
    static func normalize(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for prefix in ["https://", "http://"] where s.hasPrefix(prefix) {
            s.removeFirst(prefix.count)
        }
        if s.hasPrefix("www.") { s.removeFirst(4) }
        // corta o primeiro '/', '?', '#' ou ':' — mantém apenas o host
        if let idx = s.firstIndex(where: { $0 == "/" || $0 == "?" || $0 == "#" || $0 == ":" }) {
            s = String(s[..<idx])
        }
        return s
    }

    /// Aceita apenas hosts com pelo menos um ponto, rótulos alfanuméricos/hífen, sem hífen nas bordas.
    static func isValid(_ host: String) -> Bool {
        guard !host.isEmpty, host.count <= 253, host.contains(".") else { return false }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2 else { return false }
        for label in labels {
            guard (1...63).contains(label.count) else { return false }
            guard label.first != "-", label.last != "-" else { return false }
            let allowed = label.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" }
            guard allowed else { return false }
        }
        // o TLD (último rótulo) não pode ser puramente numérico
        if let tld = labels.last, tld.allSatisfy(\.isNumber) { return false }
        return true
    }
}
